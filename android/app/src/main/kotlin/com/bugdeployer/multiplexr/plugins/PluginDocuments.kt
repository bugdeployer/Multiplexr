package com.bugdeployer.multiplexr.plugins
import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ExecutorService
import com.bugdeployer.multiplexr.readBytesBounded

internal class PluginDocuments(private val activity:Activity,private val worker:ExecutorService,private val store:PluginStore,private val epoch:()->Long) {
    private val main=Handler(Looper.getMainLooper())
    private data class Request(val id:String,val revision:Long,val collections:Set<String>,val epoch:Long,val result:MethodChannel.Result,val text:String?=null)
    private data class Input(val request:Request,val text:String,val mime:String,val expires:Long)
    private var pending:Request?=null
    private val inputs=mutableMapOf<String,Input>()
    val busy get()=pending!=null
    fun clear() { synchronized(inputs) { inputs.clear() }; val old=pending;pending=null;old?.result?.error("cancelled","Plugin file operation cancelled",null) }
    private fun access(r:Request,permission:String) { require(epoch()==r.epoch);store.withCapability(r.id,r.revision,permission,r.collections) { } }
    fun open(args:Map<*,*>,export:Boolean,result:MethodChannel.Result) {
        require(pending==null)
        val text=if(export)args["text"] as String else null;require(text==null||text.toByteArray(Charsets.UTF_8).size<=32768)
        val request=Request(args["id"] as String,(args["revision"] as Number).toLong(),(args["collections"] as List<*>).map { it as String }.toSet(),epoch(),result,text)
        access(request,if(export)"export.create" else "import.parse")
        val intent=if(export) {
            val name=args["name"] as String;require(name.length in 1..200&&name.none { it=='/'||it=='\\'||it.code<32 })
            Intent(Intent.ACTION_CREATE_DOCUMENT).setType("text/plain").putExtra(Intent.EXTRA_TITLE,name)
        } else Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").putExtra(Intent.EXTRA_MIME_TYPES,arrayOf("text/plain","application/json","text/csv","application/octet-stream"))
        pending=request
        try { activity.startActivityForResult(intent.addCategory(Intent.CATEGORY_OPENABLE),if(export)93 else 92) } catch(e:Exception) { pending=null;throw e }
    }
    fun onResult(code:Int,status:Int,intent:Intent?):Boolean {
        if(code !in setOf(92,93))return false
        val request=pending?:return true;pending=null;val uri=intent?.data
        if(status!=Activity.RESULT_OK||uri==null) { request.result.success(null);return true }
        worker.execute { try {
            val permission=if(code==93)"export.create" else "import.parse";access(request,permission)
            val value:Any?=if(code==92) {
                val mime=activity.contentResolver.getType(uri)?:"text/plain";require(mime in setOf("text/plain","application/json","text/csv","application/octet-stream"))
                val bytes=activity.contentResolver.openInputStream(uri)!!.use { it.readBytesBounded(32768) }
                val text=Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString();access(request,permission)
                val handle=UUID.randomUUID().toString();synchronized(inputs) { inputs.entries.removeIf { it.value.expires<android.os.SystemClock.elapsedRealtime() };require(inputs.size<8);inputs[handle]=Input(request,text,mime,android.os.SystemClock.elapsedRealtime()+30000) }
                mapOf("handle" to handle,"mime" to mime)
            } else {
                // Check and hold grant serialization through the bounded write.
                store.withCapability(request.id,request.revision,permission,request.collections) {
                    require(epoch()==request.epoch)
                    activity.contentResolver.openOutputStream(uri,"wt")!!.use { it.write(request.text!!.toByteArray(Charsets.UTF_8)) }
                };true
            }
            main.post { request.result.success(value) }
        } catch(_:Exception) { main.post { request.result.error("document_operation","File operation rejected or plugin access ended",null) } } }
        return true
    }
    fun read(id:String,revision:Long,handle:String):Map<String,Any> {
        val input=synchronized(inputs) { inputs.remove(handle) }?:error("Input handle expired")
        require(input.request.id==id&&input.request.revision==revision&&input.expires>android.os.SystemClock.elapsedRealtime())
        access(input.request,"import.parse");return mapOf("text" to input.text,"mime" to input.mime)
    }
}
