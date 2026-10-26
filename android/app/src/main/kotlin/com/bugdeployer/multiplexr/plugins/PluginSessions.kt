package com.bugdeployer.multiplexr.plugins
import android.os.SystemClock
import androidx.media3.exoplayer.ExoPlayer
import com.bugdeployer.multiplexr.AudioEngine
import com.bugdeployer.multiplexr.PlaybackEngine
import org.json.JSONArray
import java.util.UUID

internal data class PluginSessionCommand(val kind: String,val milliseconds: Long?=null)
internal object PluginSessionPolicy {
    fun commands(rows: JSONArray): List<PluginSessionCommand> {
        require(rows.length() in 0..8)
        return (0 until rows.length()).map { index ->
            val row=rows.getJSONObject(index);val kind=row.getString("kind")
            if(kind=="seek") {
                PluginPackage.exact(row,setOf("kind","position"));val position=row.getJSONObject("position");PluginPackage.exact(position,setOf("kind","milliseconds"))
                require(position.getString("kind")=="time"&&(position.get("milliseconds") is Int||position.get("milliseconds") is Long)&&position.getLong("milliseconds")>=0)
                PluginSessionCommand(kind,position.getLong("milliseconds"))
            } else { PluginPackage.exact(row,setOf("kind"));require(kind in setOf("pause","resume"));PluginSessionCommand(kind) }
        }
    }
}
/** Native engines stay behind this host adapter; tokens expire and are consumed. */
internal class PluginSessions(private val store: PluginStore) {
    private data class Lease(val plugin:String,val revision:Long,val collection:String,val kind:String,val owner:String,val generation:Long,val player:ExoPlayer,val expires:Long)
    private val leases=mutableMapOf<String,Lease>()
    fun clear() { leases.clear() }
    fun list(id:String,revision:Long):List<Map<String,Any>> {
        check(android.os.Looper.myLooper()==android.os.Looper.getMainLooper())
        val p=store.packageFor(id,revision);require("sessions.control" in PluginPackage.strings(store.row(id).getJSONArray("permissions")))
        leases.entries.removeIf { it.value.expires<=SystemClock.elapsedRealtime() };require(leases.size<32)
        val allowed=PluginPackage.strings(store.row(id).getJSONArray("collections"));val result=mutableListOf<Map<String,Any>>()
        fun add(collection:String,kind:String,owner:String,player:ExoPlayer,generation:Long) {
            if(collection !in allowed||owner.isBlank())return
            val token=UUID.randomUUID().toString();leases[token]=Lease(id,revision,collection,kind,owner,generation,player,SystemClock.elapsedRealtime()+15000)
            result.add(mapOf("handle" to token,"collection" to collection,"kind" to kind,"state" to mapOf("kind" to "time","milliseconds" to player.currentPosition.coerceAtLeast(0))))
        }
        AudioEngine.current()?.let { player -> val state=AudioEngine.snapshot();state.optJSONObject("id")?.let { owner -> add(owner.getString("collectionId"),owner.getString("kind"),owner.getString("itemId"),player,AudioEngine.sessionRevision()) } }
        PlaybackEngine.current()?.takeIf { PlaybackEngine.views>0||PlaybackEngine.background }?.let { add(PlaybackEngine.collectionId,"video",PlaybackEngine.assetId,it,PlaybackEngine.libraryGeneration) }
        return result
    }
    fun apply(id:String,revision:Long,token:String,rows:JSONArray) {
        check(android.os.Looper.myLooper()==android.os.Looper.getMainLooper())
        val commands=PluginSessionPolicy.commands(rows);val lease=leases.remove(token)?:error("Session expired")
        require(lease.plugin==id&&lease.revision==revision&&lease.expires>SystemClock.elapsedRealtime())
        store.withCapability(id,revision,"sessions.control",setOf(lease.collection)) {
            if(lease.kind=="video") require(PlaybackEngine.current()===lease.player&&PlaybackEngine.collectionId==lease.collection&&PlaybackEngine.assetId==lease.owner&&PlaybackEngine.libraryGeneration==lease.generation)
            else {
                val state=AudioEngine.snapshot().getJSONObject("id")
                require(AudioEngine.current()===lease.player&&state.getString("collectionId")==lease.collection&&state.getString("itemId")==lease.owner&&state.getString("kind")==lease.kind&&AudioEngine.sessionRevision()==lease.generation)
            }
            require(commands.all { it.milliseconds==null||it.milliseconds<=(lease.player.duration.takeIf { d->d>0 }?:0) })
            for(command in commands) when(command.kind) {
                "pause" -> if(lease.kind=="video") lease.player.pause() else if(lease.player.playWhenReady) AudioEngine.toggle()
                "resume" -> if(lease.kind=="video") lease.player.play() else if(!lease.player.playWhenReady) AudioEngine.toggle()
                "seek" -> if(lease.kind=="video") lease.player.seekTo(command.milliseconds!!) else AudioEngine.seek(command.milliseconds!!)
            }
        }
    }
}
