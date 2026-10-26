package com.bugdeployer.multiplexr

import android.app.Activity
import android.content.*
import android.database.sqlite.*
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel
import org.json.*
import java.util.concurrent.Executors

class LibraryHost(private val activity: Activity, private val channel: MethodChannel, private val pluginMutation: ((Map<*, *>, () -> Unit) -> Unit)? = null, private val pluginCommit: ((Map<*, *>, () -> Unit) -> Unit)? = null) {
    private val context = activity.applicationContext
    private val resolver = context.contentResolver
    private val readingText = ReadingTextFiles(java.io.File(context.cacheDir, "reading-text")) { uri -> resolver.openInputStream(Uri.parse(uri)) ?: error("Cannot read publication.") }
    private val readingComics = ReadingComicFiles(java.io.File(context.cacheDir, "reading-comics"), ReadingAndroidSources(context))
    private val readingPdf = ReadingPdfFiles(java.io.File(context.cacheDir, "reading-pdf")) { uri -> resolver.openInputStream(Uri.parse(uri)) ?: error("Cannot read PDF.") }
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cancelled = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private var picker: MethodChannel.Result? = null
    private val helper = object : SQLiteOpenHelper(context, "library.db", null, 3) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE collections (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            db.execSQL("CREATE TABLE assets (collection_id TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(collection_id,id))")
            createSeriesTables(db)
            db.execSQL("CREATE TABLE library_state (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        }
        private fun createSeriesTables(db: SQLiteDatabase) {
            for (table in listOf("series", "seasons", "episodes")) db.execSQL("CREATE TABLE IF NOT EXISTS $table (id TEXT PRIMARY KEY, collection_id TEXT NOT NULL, payload TEXT NOT NULL)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            if (oldVersion < 2) createSeriesTables(db)
            if (oldVersion < 3) db.execSQL("CREATE TABLE library_state (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        }
    }
    private val documents = LibraryDocuments(activity, executor, main, { snapshot() })
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "exportBackup" -> documents.export(result)
                "readBackup" -> documents.read(result)
                "relinkMusic" -> {
                    val data=call.arguments as Map<*, *>;val owner=data["collectionId"] as String;val missing=data["missingId"] as String;val replacement=data["replacementId"] as String
                    AudioEngine.discard(context)
                    executor.execute {
                        try {
                            val db=helper.writableDatabase
                            LibraryStateStore.transaction(db) {
                                val catalog=LibraryStateStore.raw(db,"music:library") ?: error("Music catalog unavailable.")
                                val extras=LibraryStateStore.raw(db,"music:extras") ?: JSONObject().put("version",1).put("titles",JSONObject()).put("albums",JSONObject()).put("playlists",JSONArray())
                                val result=MusicRelinkPolicy.apply(catalog,extras,owner,missing,replacement)
                                putState(db,"music:library",result.first);putState(db,"music:extras",result.second)
                                val oldKey="progress:"+JSONArray(listOf("music",owner,missing)).toString();val newKey="progress:"+JSONArray(listOf("music",owner,replacement)).toString()
                                if(LibraryStateStore.read(db,oldKey)==null) LibraryStateStore.read(db,newKey)?.let{it.getJSONObject("id").put("itemId",missing);putState(db,oldKey,it)}
                                LibraryStateStore.delete(db,newKey)
                                LibraryStateStore.read(db,"music:session")?.let { session ->
                                    val entries=session.getJSONArray("entries");for(i in 0 until entries.length()) {val id=entries.getJSONObject(i).getJSONObject("owner");if(id.getString("collectionId")==owner && id.getString("itemId")==replacement)id.put("itemId",missing)}
                                    putState(db,"music:session",MusicSessionCodec.validate(session))
                                }
                            }
                            main.post{result.success(null)}
                        } catch(e:Exception){main.post{result.error("repair",e.message ?: "Could not reconnect this track.",null)}}
                    }
                }
                "restoreBackup" -> {
                    if (PlaybackEngine.views > 0) result.error("busy", "Close the video player before restoring the library.", null)
                    else {
                        AudioEngine.discard(context)
                        PlaybackEngine.libraryGeneration++
                        PlaybackEngine.assetId = ""; PlaybackEngine.collectionId = ""
                        PlaybackEngine.current()?.pause()
                        PlaybackEngine.setBackground(context, false)
                        executor.execute {
                            try { restore(helper.writableDatabase, BackupCodec.validate(JSONObject(call.arguments as String))); main.post { result.success(null) } }
                            catch (_: Exception) { main.post { result.error("backup", "Restore failed. The previous library was preserved.", null) } }
                        }
                    }
                }
                "scan" -> {
                    val request = ScanRequest.decode(call.arguments)
                    val id = request.id
                    cancelled.remove(id)
                    executor.execute {
                        try {
                            val db = helper.writableDatabase
                            CatalogMigration.ensure(migrationStore(db))
                            val collection = rows(db, "collections", "id=?", arrayOf(id)).firstOrNull() ?: throw IllegalArgumentException("Collection no longer exists.")
                            require(!(collection.optString("type") == "audio" && collection.optString("subtype") == "music")) { "Music uses its own source discovery and catalog reconciliation." }
                            val value = if (collection.optString("type") in listOf("audiobook", "audio")) AudioScanner(context).scan(db, collection) { cancelled.contains(id) } else scan(db, request)
                            main.post { result.success(request.result(value)) }
                        }
                        catch (e: Exception) { main.post { result.error("library", e.message ?: "Scan failed.", null) } }
                    }
                }
                "cancelScan" -> { cancelled.add(call.arguments as String); result.success(null) }
                "cancelReadingScan" -> { cancelled.add("reading:${call.arguments as String}"); result.success(null) }
                "readingTextAction" -> {
                    try {
                                val args = call.arguments as Map<*, *>; val text = args["text"] as String; require(text.length in 1..4096)
                                val intent = when (args["action"]) {
                                    "share" -> Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                                    "dictionary" -> Intent(Intent.ACTION_PROCESS_TEXT).setType("text/plain").putExtra(Intent.EXTRA_PROCESS_TEXT, text).putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
                                    else -> error("Unsupported text action")
                                }
                                require(intent.resolveActivity(activity.packageManager) != null) { "No app is available for this action." }
                                activity.startActivity(Intent.createChooser(intent, "Selected text")); result.success(null)
                                } catch (e: Exception) { result.error("text_action", e.message ?: "Cannot open selected text action.", null) }
                }
                "readingReaderApps" -> try {
                    val mime = readingMime(call.arguments as String)
                    val intent = Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse("content://multiplexr/publication"), mime)
                    val apps = activity.packageManager.queryIntentActivities(intent, 0)
                        .filter { it.activityInfo.packageName != activity.packageName }
                        .distinctBy { it.activityInfo.packageName }
                        .map { mapOf("package" to it.activityInfo.packageName, "label" to it.loadLabel(activity.packageManager).toString()) }
                    result.success(apps)
                } catch (e: Exception) { result.error("reader", "Could not find installed readers.", null) }
                "openExternalReading" -> try {
                    val a = call.arguments as Map<*, *>
                    val catalog = LibraryStateStore.raw(helper.readableDatabase, ReadingCatalogCodec.KEY) ?: error("Reading catalog is missing.")
                    val titles = catalog.getJSONArray("titles")
                    val title = (0 until titles.length()).map { titles.getJSONObject(it) }.single { it.getString("collectionId") == a["collectionId"] && it.getString("id") == a["titleId"] }
                    val source = title.getJSONObject("source")
                    require(source.getBoolean("available") && source.getString("revision") == a["revision"]) { "Publication changed or is unavailable. Scan its folder again." }
                    val uri = Uri.parse(source.getString("uri")); require(uri.scheme == "content")
                    require(resolver.persistedUriPermissions.any { it.isReadPermission && it.uri.toString() == source.getString("rootUri") }) { "Folder access is missing. Select its folder again." }
                    resolver.openAssetFileDescriptor(uri, "r").use { require(it != null) { "The file is unavailable. Repair its source folder or scan again." } }
                    val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, readingMime(title.getString("format")))
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    intent.clipData = ClipData.newRawUri("Publication", uri)
                    val target = a["package"] as? String
                    if (!target.isNullOrEmpty()) intent.setPackage(target)
                    require(intent.resolveActivity(activity.packageManager) != null) { "No compatible reader is installed. Choose another reader or use the built-in reader." }
                    activity.startActivity(if (target.isNullOrEmpty()) Intent.createChooser(intent, "Open with") else intent)
                    result.success(true)
                } catch (e: Exception) { result.error("reader", e.message ?: "Cannot open external reader.", null) }
                "cancelReadingComic" -> { cancelled.add("comic:${call.arguments as String}"); result.success(null) }
                "cancelReadingText" -> { cancelled.add("text:${call.arguments as String}"); result.success(null) }
                "pickRoot" -> {
                    if (picker != null) result.error("busy", "A folder picker is already open.", null)
                    else try {
                        picker = result
                        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION), DocumentRequest.ROOT.code)
                    } catch (e: Exception) { picker = null; result.error("folder", "Cannot open the device folder picker.", null) }
                }
                "external" -> try {
                    val uri = Uri.parse(call.arguments as String)
                    val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "video/*")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    view.clipData = ClipData.newRawUri("Video", uri)
                    activity.startActivity(Intent.createChooser(view, "Play with"))
                    result.success(null)
                } catch (e: ActivityNotFoundException) { result.error("player", "Install an external video player first.", null) }
                  catch (e: Exception) { result.error("player", "Could not open this video in another app.", null) }
                else -> executor.execute {
                    try {
                        val db = helper.writableDatabase
                            CatalogMigration.ensure(migrationStore(db))
                        val original = call
                        val commit = if (original.method == "pluginCommit") original.arguments as Map<*, *> else null
                        val call = if (commit == null) original else io.flutter.plugin.common.MethodCall(commit["method"] as String, commit["arguments"])
                        if(commit != null) require(call.method in setOf("writeState", "applyMetadata", "commitReadingManagement"))
                        var value: Any? = null
                        val operation = { value = when (call.method) {
                            "openReadingText" -> {
                                val args = call.arguments as Map<*, *>; val owner = args["collectionId"] as String; val id = args["titleId"] as String
                                val request = args["requestId"] as String; require(request.length in 1..128)
                                val catalog = LibraryStateStore.raw(db, ReadingCatalogCodec.KEY) ?: error("Reading catalog is missing.")
                                val titles = catalog.getJSONArray("titles")
                                val title = (0 until titles.length()).map { titles.getJSONObject(it) }.single { it.getString("collectionId") == owner && it.getString("id") == id }
                                if (title.getJSONObject("source").getString("revision") != args["revision"]) throw ReadingTextChanged()
                                require(title.getJSONObject("source").getBoolean("available")) { "Publication is unavailable. Repair its source first." }
                                require(resolver.persistedUriPermissions.any { it.isReadPermission && it.uri.toString() == title.getJSONObject("source").getString("rootUri") }) { "Folder grant is missing. Select its folder again." }
                                val entries = LibraryStateStore.raw(db, ReadingIndexCodec.KEY)?.getJSONArray("entries") ?: error("Index this publication first.")
                                val evidence = ReadingIndexCodec.entry(entries, owner, id)
                                try { readingText.open(title, evidence) { cancelled.contains("text:$request") } } finally { cancelled.remove("text:$request") }
                            }
                            "openReadingComic", "openReadingPdf" -> {
                                val args = call.arguments as Map<*, *>; val owner = args["collectionId"] as String; val id = args["titleId"] as String
                                val request = args["requestId"] as String; require(request.length in 1..128)
                                val catalog = LibraryStateStore.raw(db, ReadingCatalogCodec.KEY) ?: error("Reading catalog is missing.")
                                val titles = catalog.getJSONArray("titles")
                                val title = (0 until titles.length()).map { titles.getJSONObject(it) }.single { it.getString("collectionId") == owner && it.getString("id") == id }
                                if (title.getJSONObject("source").getString("revision") != args["revision"]) throw ReadingTextChanged()
                                require(title.getJSONObject("source").getBoolean("available")) { "Publication source is missing. Repair it first." }
                                val root = Uri.parse(title.getJSONObject("source").getString("rootUri"))
                                require(resolver.persistedUriPermissions.any { it.isReadPermission && it.uri == root }) { "Folder grant is missing." }
                                val entries = LibraryStateStore.raw(db, ReadingIndexCodec.KEY)?.getJSONArray("entries") ?: error("Scan the reading source first.")
                                val evidence = ReadingIndexCodec.entry(entries, owner, id)
                                try { (if (call.method == "openReadingPdf") readingPdf.open(title, evidence.getString("fingerprint")) { cancelled.contains("comic:$request") } else readingComics.open(title, evidence) { cancelled.contains("comic:$request") }).toString() } finally { cancelled.remove("comic:$request") }
                            }
                            "readingPdfInfo" -> {
                                val a = call.arguments as Map<*, *>; readingPdf.info(a["token"] as String, a["pageId"] as String).toString()
                            }
                            "readingPdfTile" -> {
                                val a = call.arguments as Map<*, *>; readingPdf.tile(a["token"] as String, a["pageId"] as String,
                                    (a["left"] as Number).toInt(), (a["top"] as Number).toInt(), (a["width"] as Number).toInt(), (a["height"] as Number).toInt(), (a["targetWidth"] as Number).toInt())
                            }
                            "closeReadingPdf" -> { readingPdf.close(call.arguments as String); null }
                            "readingComicInfo" -> {
                                val a = call.arguments as Map<*, *>; ReadingComicPixels.info(readingComics, a["token"] as String, a["pageId"] as String, a["crop"] == true).toString()
                            }
                            "readingComicTile" -> {
                                val a = call.arguments as Map<*, *>; ReadingComicPixels.tile(readingComics, a["token"] as String, a["pageId"] as String,
                                    (a["left"] as Number).toInt(), (a["top"] as Number).toInt(), (a["width"] as Number).toInt(), (a["height"] as Number).toInt(), (a["targetWidth"] as Number).toInt())
                            }
                            "closeReadingComic" -> { readingComics.close(call.arguments as String); null }
                            "readingTextResource" -> {
                                val args = call.arguments as Map<*, *>; readingText.resource(args["token"] as String, args["resourceId"] as String).json().toString()
                            }
                            "readingTextLink" -> {
                                val a = call.arguments as Map<*, *>; readingText.linkedResource(a["token"] as String, a["resourceId"] as String, a["href"] as String).json().toString()
                            }
                            "readingTextImage" -> {
                                val a = call.arguments as Map<*, *>; readingText.image(a["token"] as String, a["resourceId"] as String, a["href"] as String)
                            }
                            "readingTextContents" -> readingText.contents(call.arguments as String).toString()
                            "searchReadingText" -> {
                                val args = call.arguments as Map<*, *>; val request = args["requestId"] as String
                                try { readingText.search(args["token"] as String, args["query"] as String) { cancelled.contains("text:$request") }.toString() }
                                finally { cancelled.remove("text:$request") }
                            }
                            "closeReadingText" -> { readingText.close(call.arguments as String); null }
                            "readingCacheInfo" -> JSONObject().put("bytes", readingText.cacheBytes() + readingComics.cacheBytes() + readingPdf.cacheBytes()).toString()
                            "clearReadingIdleCache" -> { readingText.clearIdleCache(); readingComics.clearIdleCache(); readingPdf.clearIdleCache(); null }
                            "readingSnapshot" -> JSONObject().put("catalog", LibraryStateStore.raw(db, ReadingCatalogCodec.KEY) ?: JSONObject.NULL)
                                .put("index", LibraryStateStore.raw(db, ReadingIndexCodec.KEY) ?: JSONObject.NULL)
                                .put("management", LibraryStateStore.raw(db, ReadingManagementCodec.KEY) ?: JSONObject.NULL).toString()
                            "commitReadingManagement" -> {
                                val data = JSONObject(call.arguments as String); val owner = data.getString("collectionId")
                                LibraryStateStore.transaction(db) {
                                    ReadingManagementCodec.checkCommit(owner, LibraryStateStore.raw(db, ReadingCatalogCodec.KEY), LibraryStateStore.raw(db, ReadingIndexCodec.KEY), LibraryStateStore.raw(db, ReadingManagementCodec.KEY), data)
                                    val catalog = data.getJSONObject("catalog")
                                    ReadingCatalogCodec.requireSeparateOwners(catalog, rows(db, "collections").map { it.getString("id") }.toSet())
                                    val index = ReadingArtworkFiles.transform(context, data.getJSONObject("index"), false)
                                    val management = ReadingArtworkFiles.transformManagement(context, data.getJSONObject("management"), false)
                                    ReadingIndexCodec.validate(index, catalog); ReadingManagementCodec.validate(management, catalog)
                                    LibraryStateStore.put(db, ReadingCatalogCodec.KEY, catalog)
                                    LibraryStateStore.put(db, ReadingIndexCodec.KEY, index)
                                    LibraryStateStore.put(db, ReadingManagementCodec.KEY, management)
                                    LibraryStateStore.raw(db, ReadingAnnotationsCodec.KEY)?.let { LibraryStateStore.put(db, ReadingAnnotationsCodec.KEY, ReadingAnnotationsCodec.retain(it, catalog)) }
                                }
                                null
                            }
                            "readReadingArtwork" -> ReadingArtworkFiles.read(context, call.arguments as String)
                            "storeReadingArtwork" -> ReadingArtworkFiles.store(context, call.arguments as ByteArray)
                            "discoverReading" -> {
                                val data = call.arguments as Map<*, *>
                                val request = ScanRequest.decode(data)
                                val token = request.requestId ?: error("Reading scan requires request identity.")
                                val collection = JSONObject(data["collection"] as Map<*, *>)
                                val stored = LibraryStateStore.raw(db, ReadingCatalogCodec.KEY)?.getJSONArray("collections") ?: error("No reading collections.")
                                require((0 until stored.length()).any { stored.getJSONObject(it).getString("id") == request.id && stored.getJSONObject(it).getString("subtype") == collection.getString("subtype") })
                                require(collection.getString("id") == request.id)
                                val encodings = mutableMapOf<String, String>()
                                LibraryStateStore.raw(db, ReadingIndexCodec.KEY)?.getJSONArray("entries")?.let { entries ->
                                    for (i in 0 until entries.length()) { val e = entries.getJSONObject(i); if (e.getString("collectionId") == request.id && e.getString("encoding").isNotEmpty()) encodings[e.getString("sourceKey")] = e.getString("encoding") }
                                }
                                (data["encodings"] as? Map<*, *>)?.let { values ->
                                    require(values.size <= 200000)
                                    for ((key, value) in values) { require(key is String && value is String && value in setOf("utf-8", "utf-16le", "utf-16be", "windows-1252")); encodings[key] = value }
                                }
                                try {
                                    val temporary = java.io.File(context.cacheDir, "reading-index")
                                    ReadingPublication.clearAbandoned(temporary)
                                    val preferences = LibraryStateStore.raw(db, ReadingManagementCodec.KEY)?.optJSONArray("collections")
                                    var formats: Set<String>? = null
                                    if(preferences != null) for(i in 0 until preferences.length()) {
                                        val pref=preferences.getJSONObject(i)
                                        if(pref.getString("collectionId")==request.id && pref.has("formats")) {
                                            val values=pref.getJSONArray("formats");formats=(0 until values.length()).map{values.getString(it)}.toSet()
                                        }
                                    }
                                    val value = ReadingSourceDiscovery(ReadingAndroidSources(context) { cancelled.contains("reading:$token") }, temporary, formats)
                                        .discover(collection, token, data["encoding"] as? String ?: "utf-8", encodings, { cancelled.contains("reading:$token") }) { found, folder ->
                                            main.post { channel.invokeMethod("scanProgress", request.progress(found, folder)) }
                                        }
                                    value.toString()
                                } finally { cancelled.remove("reading:$token") }
                            }
                            "commitReadingScan" -> {
                                val data = JSONObject(call.arguments as String)
                                val owner = data.getString("collectionId")
                                val next = data.getJSONObject("catalog"); val index = data.getJSONObject("index")
                                LibraryStateStore.transaction(db) {
                                    ReadingIndexCodec.checkCommit(owner, LibraryStateStore.raw(db, ReadingCatalogCodec.KEY), LibraryStateStore.raw(db, ReadingIndexCodec.KEY),
                                        data.optJSONObject("expectedCatalog"), data.optJSONObject("expectedIndex"), next, index)
                                    ReadingCatalogCodec.requireSeparateOwners(next, rows(db, "collections").map { it.getString("id") }.toSet())
                                    val localIndex = ReadingArtworkFiles.transform(context, index, portable = false)
                                    ReadingIndexCodec.validate(localIndex, next)
                                    LibraryStateStore.put(db, ReadingCatalogCodec.KEY, next)
                                    LibraryStateStore.put(db, ReadingIndexCodec.KEY, localIndex)
                                    LibraryStateStore.raw(db, ReadingAnnotationsCodec.KEY)?.let { LibraryStateStore.put(db, ReadingAnnotationsCodec.KEY, ReadingAnnotationsCodec.retain(it, next)) }
                                    LibraryStateStore.raw(db, ReadingManagementCodec.KEY)?.let { LibraryStateStore.put(db, ReadingManagementCodec.KEY, ReadingManagementCodec.retain(it, next)) }
                                }
                                null
                            }
                            "metadataConfigured" -> false
                            "saveToken", "metadataSearch", "artwork", "metadataDetails" -> error("Use an installed metadata provider through the plugin gateway.")
                            "discoverMusic" -> {
                                val request=ScanRequest.decode(call.arguments)
                                val id=request.id
                                cancelled.remove(id)
                                val collection=rows(db,"collections","id=?",arrayOf(id)).firstOrNull() ?: error("Collection no longer exists.")
                                try { map(AudioSourceDiscovery(context).discover(collection,{cancelled.contains(id)}) { found,folder ->
                                    main.post { channel.invokeMethod("scanProgress",request.progress(found,folder)) }
                                }) } catch(e:Exception) {
                                    val roots=collection.getJSONArray("roots")
                                    val health=JSONObject();for(i in 0 until roots.length()) health.put(roots.getJSONObject(i).getString("uri"),"Scan interrupted — verify folder access")
                                    collection.put("rootHealth",health)
                                    db.update("collections",ContentValues().apply{put("payload",collection.toString())},"id=?",arrayOf(id))
                                    throw e
                                }
                            }
                            "readState" -> {
                                val key = call.arguments as String
                                val raw = LibraryStateStore.read(db,key)
                                if(raw != null && key in setOf("music:library","music:extras")) {
                                    val compact=MusicArtworkFiles.transform(context,raw)
                                    if(compact.toString()!=raw.toString()) putState(db,key,compact)
                                    compact.toString()
                                } else raw?.toString()
                            }
                            "readStates" -> {
                                val keys = call.arguments as List<*>
                                require(keys.size <= 400 && keys.all { it is String })
                                JSONObject().apply { for (key in keys) put(key as String, LibraryStateStore.read(db, key) ?: JSONObject.NULL) }.toString()
                            }
                            "writeState" -> {
                                val data = call.arguments as Map<*, *>
                                val key = MediaStateKeys.canonical(data["key"] as String)
                                require(CollectionStatePolicy.writable(key, data["value"] == null))
                                val value = data["value"] as? String
                                if (value == null) LibraryStateStore.transaction(db) {
                                    LibraryStateStore.delete(db, key)
                                    if (key == ReadingCatalogCodec.KEY) LibraryStateStore.delete(db, ReadingIndexCodec.KEY)
                                    if (key == ReadingCatalogCodec.KEY) { LibraryStateStore.delete(db, ReadingAnnotationsCodec.KEY); LibraryStateStore.delete(db, ReadingManagementCodec.KEY) }
                                }
                                else {
                                    require(value.length <= 10_000_000)
                                    val parsed = if (key.startsWith("progress:") || key.startsWith("queue:")) DurableMediaStateCodec.validate(key, JSONObject(value)) else JSONObject(value)
                                    if (key == ReadingAnnotationsCodec.KEY) ReadingAnnotationsCodec.validate(parsed, LibraryStateStore.raw(db, ReadingCatalogCodec.KEY) ?: error("Reading catalog is missing."))
                                    if (key == ReadingCatalogCodec.KEY) {
                                        ReadingCatalogCodec.validate(parsed)
                                        ReadingCatalogCodec.requireSeparateOwners(parsed, rows(db, "collections").map { it.getString("id") }.toSet())
                                    }
                                    if (key.startsWith("media:settings:")) MediaSettingsCodec.validate(key, parsed)
                                    if (key.startsWith("ui:browse:")) BrowseStateCodec.validate(key, parsed)
                                    if (key.startsWith("spaces:audiobooks:")) SpacePreferencesCodec.validate(JSONObject().put("audiobooks", parsed))
                                    if (key == PlayerPreferencesCodec.KEY) PlayerPreferencesCodec.validate(parsed)
                                    if (key == JobReceiptCodec.KEY) JobReceiptCodec.validate(parsed)
                                    if (key == "spaces:display") SpacePreferencesCodec.validate(parsed)
                                    if (key == "music:extras") MusicExtrasCodec.validate(parsed, rows(db, "collections").filter { it.optString("type") == "audio" && it.optString("subtype") == "music" }.map { it.getString("id") }.toSet())
                                    if (key.startsWith("spaces:music:")) SpacePreferencesCodec.validate(JSONObject().put("music", parsed))
                                    if (key == "music:library") {
                                        MusicCatalogCodec.validate(parsed)
                                        val owners = rows(db, "collections").filter { it.optString("type") == "audio" && it.optString("subtype") == "music" }.map { it.getString("id") }.toSet()
                                        val tracks = parsed.getJSONArray("tracks")
                                        require((0 until tracks.length()).all { tracks.getJSONObject(it).getJSONObject("id").getString("collectionId") in owners }) { "A Music collection no longer exists." }
                                    }
                                    if (key == "audio:library") {
                                        AudioCatalogCodec.validate(parsed)
                                        db.beginTransaction()
                                        try {
                                            val previous = rows(db, "library_state", "id=?", arrayOf(key)).firstOrNull()?.optJSONArray("books") ?: JSONArray()
                                            val next = parsed.getJSONArray("books")
                                            val keep = (0 until next.length()).map { next.getJSONObject(it).getJSONObject("id").let { a -> JSONArray(listOf(a.getString("collectionId"), a.getString("itemId"))).toString() } }.toSet()
                                            for (i in 0 until previous.length()) {
                                                val id = previous.getJSONObject(i).getJSONObject("id")
                                                if (JSONArray(listOf(id.getString("collectionId"), id.getString("itemId"))).toString() !in keep) {
                                                    val progress = "progress:" + JSONArray(listOf("audiobook", id.getString("collectionId"), id.getString("itemId"))).toString()
                                                    LibraryStateStore.delete(db, progress)
                                                }
                                            }
                                            AudioScanner.save(db, parsed)
                                            db.setTransactionSuccessful()
                                        } finally { db.endTransaction() }
                                    } else putState(db, key, if(key in setOf("music:library","music:extras")) MusicArtworkFiles.transform(context,parsed) else parsed)
                                }
                                null
                            }
                            "pluginFields" -> {
                                val args=call.arguments as Map<*,*>;val permit=pluginMutation ?: error("Plugin gateway unavailable")
                                val key=args["key"] as String;require(ExtensionFieldsCodec.owner(key)==args["collection"])
                                permit(args) { LibraryStateStore.transaction(db) {
                                    val before=LibraryStateStore.raw(db,key)
                                    require((before?.toString())==(args["expected"] as? String)?.let { JSONObject(it).toString() }) { "Extension fields changed; reopen review" }
                                    val value=ExtensionFieldsCodec.merge(key,before,args["plugin"] as String,JSONObject(args["fields"] as Map<*,*>),args["operation"] as String)
                                    LibraryStateStore.put(db,key,value)
                                } };null
                            }
                            "pluginTags" -> { val args=call.arguments as Map<*, *>; val permit=pluginMutation ?: error("Plugin gateway unavailable"); permit(args) { pluginTags(db,args) }; null }
                            "editTags" -> { editTags(db, call.arguments as Map<*, *>); null }
                            "saveQueue" -> { putState(db, "legacyVideoQueue", JSONObject().put("items", JSONArray(call.arguments as List<*>))); null }
                            "load" -> {
                                val books = AudioScanner.catalog(db).getJSONArray("books")
                                val counts = mutableMapOf<String, Int>()
                                for (i in 0 until books.length()) {
                                    val owner = books.getJSONObject(i).getJSONObject("id").getString("collectionId")
                                    counts[owner] = (counts[owner] ?: 0) + 1
                                }
                                LibraryStateStore.raw(db, "music:library")?.getJSONArray("tracks")?.let { tracks ->
                                    for (i in 0 until tracks.length()) { val owner = tracks.getJSONObject(i).getJSONObject("id").getString("collectionId"); counts[owner] = (counts[owner] ?: 0) + 1 }
                                }
                                mapOf("seriesIndexSupported" to true, "audioCounts" to counts, "queue" to convert(videoQueue(db)), "collections" to rows(db, "collections").map { map(it) }, "assets" to rows(db, "assets").map { map(it) })
                            }
                            "saveSeriesIndex" -> {
                                val data = JSONObject(call.arguments as String)
                                val collections = rows(db, "collections").map { it.getString("id") }.toSet()
                                db.beginTransaction()
                                try {
                                    for (table in listOf("series", "seasons", "episodes")) {
                                        db.delete(table, null, null)
                                        val records = data.getJSONArray(table)
                                        for (i in 0 until records.length()) {
                                            val record = records.getJSONObject(i)
                                            if (record.getString("collectionId") !in collections) continue
                                            db.insertWithOnConflict(table, null, ContentValues().apply { put("id", record.getString("id")); put("collection_id", record.getString("collectionId")); put("payload", record.toString()) }, SQLiteDatabase.CONFLICT_REPLACE)
                                        }
                                    }
                                    db.setTransactionSuccessful()
                                } finally { db.endTransaction() }
                                null
                            }
                            "updateFlags" -> {
                                val data = call.arguments as Map<*, *>
                                val action = data["action"] as String
                                require(action in listOf("favorite", "watchLater", "watched", "clearMatches", "hideContinue"))
                                val enabled = data["value"] == true
                                db.beginTransaction()
                                try {
                                    for (selected in data["assets"] as List<*>) {
                                        val key = selected as Map<*, *>
                                        val asset = rows(db, "assets", "collection_id=? AND id=?", arrayOf(key["collectionId"] as String, key["id"] as String)).firstOrNull() ?: continue
                                        if (!AssetFlags.apply(asset, action, enabled)) continue
                                        upsert(db, asset)
                                    }
                                    db.setTransactionSuccessful()
                                } finally { db.endTransaction() }
                                null
                            }
                            "saveBrowsing" -> {
                                val data = call.arguments as Map<*, *>
                                val item = rows(db, "collections", "id=?", arrayOf(data["id"] as String)).firstOrNull()
                                if (item != null) {
                                    val values = data["values"] as Map<*, *>
                                    for (field in listOf("view", "allowFolders", "sort", "filter", "cardSize", "scrollOffset", "folder")) {
                                        if (values.containsKey(field)) item.put(field, values[field])
                                    }
                                    db.update("collections", ContentValues().apply { put("payload", item.toString()) }, "id=?", arrayOf(data["id"] as String))
                                }
                                null
                            }
                            "saveCollection" -> {
                                val item = JSONObject(call.arguments as String)
                                LibraryStateStore.raw(db, ReadingCatalogCodec.KEY)?.let { ReadingCatalogCodec.requireSeparateOwners(it, setOf(item.getString("id"))) }
                                require(item.getString("type") in listOf("video", "audiobook", "audio") && item.getString("subtype") in if (item.getString("type") == "audio") listOf("audiobooks", "music") else listOf("videos", "cinema", "movies", "tv"))
                                require(item.getString("name").trim().isNotEmpty())
                                require(item.getJSONArray("extensions").length() > 0)
                                val stored = rows(db, "collections", "id=?", arrayOf(item.getString("id"))).firstOrNull()
                                require(stored == null || (if (stored.optString("type") == "audiobook") "audio" else stored.optString("type", "video")) == item.getString("type")) { "Collection media type cannot change." }
                                // Scan health is native-owned; a queued preference save must not overwrite a completed scan.
                                if (stored != null) for (field in listOf("lastScanAt", "rootHealth")) {
                                    if (stored.has(field)) item.put(field, stored.get(field))
                                }
                                val knownRoots = stored?.optJSONArray("roots")?.let { a -> (0 until a.length()).map { a.getJSONObject(it).getString("uri") } } ?: emptyList()
                                val roots = item.getJSONArray("roots")
                                for (i in 0 until roots.length()) {
                                    val uri = Uri.parse(roots.getJSONObject(i).getString("uri"))
                                    require(uri.toString() in knownRoots || resolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }) { "Folder access has expired. Select the folder again." }
                                    if (item.getString("type") == "video" && item.getString("subtype") == "cinema") {
                                        val type = roots.getJSONObject(i).optString("contentSubtype", "movies")
                                        require(type in listOf("movies", "tv")) { "Choose Movies or TV shows for each root folder." }
                                        val path = DocumentsContract.getTreeDocumentId(uri).trimEnd('/')
                                        for (j in 0 until i) {
                                            val other = roots.getJSONObject(j)
                                            val otherUri = Uri.parse(other.getString("uri"))
                                            val otherPath = DocumentsContract.getTreeDocumentId(otherUri).trimEnd('/')
                                            require(uri.authority != otherUri.authority || type == other.optString("contentSubtype", "movies") ||
                                                !(path == otherPath || path.startsWith("$otherPath/") || otherPath.startsWith("$path/"))) {
                                                "Movies and TV roots must not overlap. Select separate folders for each content type."
                                            }
                                        }
                                    }
                                }
                                val id = item.getString("id")
                                db.insertWithOnConflict("collections", null, ContentValues().apply { put("id", id); put("payload", item.toString()) }, SQLiteDatabase.CONFLICT_REPLACE)
                                null
                            }
                            "releaseRoots" -> {
                                val used = rows(db, "collections").flatMap { collection ->
                                    val roots = collection.getJSONArray("roots")
                                    (0 until roots.length()).map { roots.getJSONObject(it).getString("uri") }
                                }.toMutableSet()
                                LibraryStateStore.raw(db, ReadingCatalogCodec.KEY)?.getJSONArray("collections")?.let { collections ->
                                    for (i in 0 until collections.length()) {
                                        val roots = collections.getJSONObject(i).getJSONArray("roots")
                                        for (j in 0 until roots.length()) used.add(roots.getJSONObject(j).getString("uri"))
                                    }
                                }
                                for (uri in call.arguments as List<*>) {
                                    if (uri is String && uri !in used) try { resolver.releasePersistableUriPermission(Uri.parse(uri), Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) {}
                                }
                                null
                            }
                            "removeCollection" -> {
                                val id = call.arguments as String
                                db.beginTransaction()
                                try {
                                    AudioScanner.removeCollection(db, id)
                                    for ((key, value) in rowsWithIds(db)) {
                                        val next = CollectionStatePolicy.withoutCollection(key, value, id)
                                        if (next == null) db.delete("library_state", "id=?", arrayOf(key))
                                        else if (next.toString() != value.toString()) putState(db, key, next)
                                    }
                                    CatalogMigration.forgetCollection(LibraryStateStore.migrationStore(db), id)
                                    val remainingQueue = JSONArray(); val oldQueue = videoQueue(db)
                                    for (i in 0 until oldQueue.length()) { val key = oldQueue.getString(i); if (JSONArray(key).optString(0) != id) remainingQueue.put(key) }
                                    putState(db, "legacyVideoQueue", JSONObject().put("items", remainingQueue))
                                    db.delete("assets", "collection_id=?", arrayOf(id)); db.delete("collections", "id=?", arrayOf(id)); for (table in listOf("series", "seasons", "episodes")) db.delete(table, "collection_id=?", arrayOf(id)); db.setTransactionSuccessful()
                                }
                                finally { db.endTransaction() }
                                null // Index entries only. Source documents are never deleted.
                            }
                            "cacheArtwork" -> error("Use an installed artwork provider through the plugin gateway.")
                            "saveGrouping" -> {
                                val edits = JSONArray(call.arguments as String)
                                require(edits.length() in 1..10000)
                                db.beginTransaction()
                                try {
                                    for (i in 0 until edits.length()) {
                                        val edit = edits.getJSONObject(i)
                                        val asset = rows(db, "assets", "collection_id=? AND id=?", arrayOf(edit.getString("collectionId"), edit.getString("id"))).firstOrNull() ?: error("Video no longer exists.")
                                        val metadata = asset.optJSONObject("metadata") ?: JSONObject()
                                        val changes = edit.getJSONObject("metadata")
                                        for (key in listOf("series", "season", "episode", "groupId", "groupOrder")) if (changes.has(key)) {
                                            require(changes.get(key) is String && changes.getString(key).length <= 500)
                                            metadata.put(key, changes.getString(key))
                                        }
                                        asset.put("metadata", metadata).put("metadataSource", "manual")
                                        upsert(db, asset)
                                    }
                                    db.setTransactionSuccessful()
                                } finally { db.endTransaction() }
                                null
                            }
                            "applyMetadata" -> {
                                val request = JSONObject(call.arguments as String)
                                val source = rows(db, "assets", "collection_id=? AND id=?", arrayOf(request.getString("collectionId"), request.getString("id"))).firstOrNull() ?: throw MetadataConflict()
                                val prepared = MetadataPatch.apply(source, request)
                                // Downloads run before the transaction; recheck the sparse
                                // patch against the latest row before the atomic commit.

                                db.beginTransaction()
                                try {
                                    val current = rows(db, "assets", "collection_id=? AND id=?", arrayOf(request.getString("collectionId"), request.getString("id"))).firstOrNull() ?: throw MetadataConflict()
                                    val updated = MetadataPatch.apply(current, request)
                                    for ((remote, local) in listOf("poster" to "localPoster", "backdrop" to "localBackdrop", "seriesBackdrop" to "localSeriesBackdrop")) {
                                        if (updated.optString(remote) == prepared.optString(remote) && prepared.has(local)) updated.put(local, prepared.get(local))
                                    }
                                    upsert(db, updated)
                                    db.setTransactionSuccessful()
                                } finally { db.endTransaction() }
                                null
                            }
                            "saveAsset", "saveMatchedAsset" -> {
                                val asset = JSONObject(call.arguments as String)
                                db.beginTransaction()
                                try {
                                require(rows(db, "assets", "collection_id=? AND id=?", arrayOf(asset.getString("collectionId"), asset.getString("id"))).isNotEmpty())
                                val previous = rows(db, "assets", "collection_id=? AND id=?", arrayOf(asset.getString("collectionId"), asset.getString("id"))).first()
                                for (key in listOf("metadata", "poster", "backdrop", "providerId", "metadataSource", "metadataStatus", "localPoster", "localBackdrop", "seriesId", "episodeId", "seriesBackdrop", "localSeriesBackdrop")) {
                                    if (asset.has(key)) previous.put(key, asset.get(key))
                                }
                                // Online responses can arrive after an independent tag edit.
                                if (call.method == "saveMatchedAsset") {
                                    val latest = rows(db, "assets", "collection_id=? AND id=?", arrayOf(asset.getString("collectionId"), asset.getString("id"))).first()
                                    val metadata = previous.optJSONObject("metadata") ?: JSONObject()
                                    val tags = latest.optJSONObject("metadata")?.optString("tags", "") ?: ""
                                    metadata.put("tags", tags)
                                    val curated = latest.optJSONObject("metadata") ?: JSONObject()
                                    for (key in listOf("groupId", "groupOrder")) if (curated.has(key)) metadata.put(key, curated.get(key))
                                    if (curated.optString("groupId").isNotBlank()) for (key in listOf("series", "season", "episode")) if (curated.has(key)) metadata.put(key, curated.get(key))
                                    previous.put("metadata", metadata)
                                }
                                upsert(db, previous)
                                db.setTransactionSuccessful()
                                } finally { db.endTransaction() }
                                null
                            }
                            "watchState" -> {
                                val data = call.arguments as Map<*, *>
                                db.beginTransaction()
                                try {
                                    val asset = rows(db, "assets", "collection_id=? AND id=?", arrayOf(data["collectionId"] as String, data["id"] as String)).firstOrNull() ?: error("Video no longer exists.")
                                    when (data["action"]) {
                                        "start" -> WatchProgress.start(asset)
                                        "watched" -> asset.put("watched", true).put("completedAt", System.currentTimeMillis()).put("positionMs", 0)
                                        "unwatched" -> asset.put("watched", false).put("completedAt", 0).put("positionMs", 0).put("hiddenFromContinue", false)
                                        "restart" -> asset.put("positionMs", 0).put("watched", false).put("completedAt", 0).put("hiddenFromContinue", false)
                                        "hide" -> asset.put("hiddenFromContinue", true)
                                        else -> error("Unknown watch action")
                                    }
                                    upsert(db, asset); db.setTransactionSuccessful()
                                } finally { db.endTransaction() }
                                null
                            }
                            "writeVideoProgress" -> {
                                val progress = JSONObject(call.arguments as String)
                                val key = progress.getJSONObject("id")
                                require(key.getString("kind") == "video")
                                require(progress.getLong("positionMs") >= 0 && progress.getLong("durationMs") >= 0)
                                db.beginTransaction()
                                try {
                                    val asset = rows(db, "assets", "collection_id=? AND id=?", arrayOf(key.getString("collectionId"), key.getString("itemId"))).firstOrNull() ?: error("Video no longer exists.")
                                    val wasWatched = asset.optBoolean("watched")
                                    asset.put("positionMs", progress.getLong("positionMs")).put("durationMs", progress.getLong("durationMs")).put("watched", progress.getBoolean("watched"))
                                    if (wasWatched != progress.getBoolean("watched")) asset.put("completedAt", if (progress.getBoolean("watched")) System.currentTimeMillis() else 0)
                                    upsert(db, asset); db.setTransactionSuccessful()
                                } finally { db.endTransaction() }
                                null
                            }
                            "position" -> {
                                val data = call.arguments as Map<*, *>
                                db.beginTransaction()
                                try {
                                    val existing = rows(db, "assets", "collection_id=? AND id=?", arrayOf(data["collectionId"] as String, data["id"] as String)).firstOrNull()
                                    if (existing != null) {
                                        WatchProgress.apply(existing, (data["positionMs"] as Number).toLong(), (data["durationMs"] as? Number)?.toLong() ?: 0)
                                        upsert(db, existing)
                                    }
                                    db.setTransactionSuccessful()
                                } finally { db.endTransaction() }
                                null
                            }
                            else -> throw IllegalArgumentException("Unknown library operation")
                        }
                        ; Unit }
                        if(commit == null) operation() else (pluginCommit ?: error("Plugin commit authority unavailable"))(commit["identity"] as Map<*, *>, operation)
                        main.post { result.success(value) }
                    } catch (e: Exception) { main.post { result.error(when (e) { is java.net.UnknownHostException, is java.net.SocketTimeoutException, is java.net.ConnectException -> "network"; is SQLiteException -> "storage"; is MetadataConflict, is ReadingManagementConflict, is ReadingScanConflict, is ReadingTextChanged -> "conflict"; is ReadingScanCancelled -> "cancelled"; else -> "library" }, e.message ?: "Library operation failed.", null) } }
                }
            }
        }
    }
    private fun migrationStore(db: SQLiteDatabase) = LibraryStateStore.migrationStore(db) {
        JSONObject().put("items", JSONArray(context.getSharedPreferences("multiplexr_queue", Context.MODE_PRIVATE).getString("items", "[]")))
    }
    private fun putState(db: SQLiteDatabase, key: String, value: JSONObject) {
        LibraryStateStore.transaction(db) {
            if (key == ReadingCatalogCodec.KEY) LibraryStateStore.raw(db, ReadingIndexCodec.KEY)?.let { index ->
                LibraryStateStore.put(db, ReadingIndexCodec.KEY, ReadingIndexCodec.retain(index, value))
            }
            if (key == ReadingCatalogCodec.KEY) LibraryStateStore.raw(db, ReadingAnnotationsCodec.KEY)?.let { annotations ->
                LibraryStateStore.put(db, ReadingAnnotationsCodec.KEY, ReadingAnnotationsCodec.retain(annotations, value))
            }
            if (key == ReadingCatalogCodec.KEY) LibraryStateStore.raw(db, ReadingManagementCodec.KEY)?.let { management ->
                LibraryStateStore.put(db, ReadingManagementCodec.KEY, ReadingManagementCodec.retain(management, value))
            }
            LibraryStateStore.put(db, key, value)
        }
    }
    private fun videoQueue(db: SQLiteDatabase): JSONArray = LibraryStateStore.raw(db, "legacyVideoQueue")?.optJSONArray("items") ?: JSONArray()
    private fun snapshot(): String {
        val db = helper.writableDatabase
        CatalogMigration.ensure(migrationStore(db))
        db.beginTransactionNonExclusive()
        try {
            val snapshot = BackupCodec.export(rows(db, "collections"), rows(db, "assets"), videoQueue(db),
                rowsWithIds(db).filterKeys(CollectionStatePolicy::exportable) + mapOf(com.bugdeployer.multiplexr.plugins.PluginPortable.KEY to com.bugdeployer.multiplexr.plugins.PluginPortable.merge(com.bugdeployer.multiplexr.plugins.PluginPortable.read(java.io.File(context.noBackupFilesDir,"plugin-platform")), LibraryStateStore.raw(db,com.bugdeployer.multiplexr.plugins.PluginPortable.KEY)))).toString()
            db.setTransactionSuccessful()
            return snapshot
        } finally { db.endTransaction() }
    }
    private fun rowsWithIds(db: SQLiteDatabase): Map<String, JSONObject> = db.query("library_state", arrayOf("id", "payload"), null, null, null, null, null).use { c ->
        buildMap { while (c.moveToNext()) { val key=c.getString(0);val value=JSONObject(c.getString(1));put(key,if(key==ReadingIndexCodec.KEY) ReadingArtworkFiles.transform(context,value,portable=true) else if(key==ReadingManagementCodec.KEY) ReadingArtworkFiles.transformManagement(context,value,true) else if(key=="music:library") MusicCatalogCodec.packArtwork(MusicArtworkFiles.transform(context,value,portable=true)) else if(key=="music:extras") MusicArtworkFiles.transform(context,value,portable=true) else value) } }
    }
    private fun restore(db: SQLiteDatabase, backup: JSONObject) {
        db.beginTransaction()
        try {
            for (table in listOf("assets", "collections", "series", "seasons", "episodes", "library_state")) db.delete(table, null, null)
            val collections = backup.getJSONArray("collections")
            for (i in 0 until collections.length()) {
                val grants = resolver.persistedUriPermissions.filter { it.isReadPermission }.map { it.uri.toString() }.toSet()
                val item = RestoreReconciliation.collection(collections.getJSONObject(i), grants)
                check(db.insertOrThrow("collections", null, ContentValues().apply { put("id", item.getString("id")); put("payload", item.toString()) }) != -1L)
            }
            val assets = backup.getJSONArray("assets")
            for (i in 0 until assets.length()) upsert(db, assets.getJSONObject(i).put("available", false))
            putState(db, "legacyVideoQueue", JSONObject().put("items", backup.getJSONArray("queue")))
            val state = backup.getJSONObject("state")
            for (key in state.keys()) {
                val value = state.getJSONObject(key)
                putState(db, key, when (key) {
                    ReadingCatalogCodec.KEY -> ReadingIndexCodec.restoredCatalog(value)
                    ReadingIndexCodec.KEY -> ReadingIndexCodec.restoredIndex(ReadingArtworkFiles.transform(context, value, portable = false))
                    ReadingManagementCodec.KEY -> ReadingArtworkFiles.transformManagement(context, value, false)
                    "music:library", "music:extras" -> MusicArtworkFiles.transform(context, value)
                    else -> value
                })
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    private fun pluginTags(db: SQLiteDatabase, data: Map<*, *>) {
        val key = data["idempotencyKey"] as String
        require(key.length in 1..256)
        val expected = JSONObject(data["expected"] as String)
        val collection = data["collection"] as String; val id = data["id"] as String
        require(expected.getString("collectionId") == collection && expected.getString("id") == id)
        val tags = TagOperations.normalize(data["tags"] as List<*>)
        val signature = com.bugdeployer.multiplexr.plugins.PluginPackage.sha((com.bugdeployer.multiplexr.plugins.PluginPackage.canonical(expected) + "\n" + JSONArray(tags).toString()).toByteArray(Charsets.UTF_8))
        db.execSQL("CREATE TABLE IF NOT EXISTS plugin_mutations (id TEXT PRIMARY KEY, signature TEXT NOT NULL)")
        db.beginTransaction()
        try {
            val old = db.rawQuery("SELECT signature FROM plugin_mutations WHERE id=?", arrayOf(key)).use { if(it.moveToFirst()) it.getString(0) else null }
            if(old != null) require(old == signature) { "Idempotency conflict" }
            else {
                val count = db.rawQuery("SELECT COUNT(*) FROM plugin_mutations",null).use { it.moveToFirst(); it.getInt(0) }
                require(count < 10000) { "Mutation receipt quota exceeded" }
                val current = rows(db,"assets","collection_id=? AND id=?",arrayOf(collection,id)).single()
                require(com.bugdeployer.multiplexr.plugins.PluginPackage.canonical(current) == com.bugdeployer.multiplexr.plugins.PluginPackage.canonical(expected)) { "Catalog revision conflict" }
                editTags(db,mapOf("operation" to "replace", "tags" to tags, "assets" to listOf(mapOf("collectionId" to collection,"id" to id))))
                db.insertOrThrow("plugin_mutations",null,ContentValues().apply { put("id",key); put("signature",signature) })
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    private fun editTags(db: SQLiteDatabase, data: Map<*, *>) {
        val operation = data["operation"] as String
        require(operation in listOf("add", "remove", "replace", "rename", "delete"))
        val tags = TagOperations.normalize(data["tags"] as List<*>)
        val target = (data["target"] as? String)?.trim()
        val collection = data["collectionId"] as? String
        db.beginTransaction()
        try {
            val selected = if (operation in listOf("rename", "delete")) {
                require(!collection.isNullOrEmpty())
                rows(db, "assets", "collection_id=?", arrayOf(collection))
            } else (data["assets"] as List<*>).mapNotNull { value ->
                val key = value as Map<*, *>
                rows(db, "assets", "collection_id=? AND id=?", arrayOf(key["collectionId"] as String, key["id"] as String)).firstOrNull()
            }
            for (asset in selected) {
                val metadata = asset.optJSONObject("metadata") ?: JSONObject()
                metadata.put("tags", TagOperations.apply(metadata.optString("tags"), operation, tags, target).joinToString(", "))
                asset.put("metadata", metadata)
                upsert(db, asset)
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    private fun rows(db: SQLiteDatabase, table: String, where: String? = null, args: Array<String>? = null): List<JSONObject> =
        db.query(table, arrayOf("payload"), where, args, null, null, "rowid ASC").use { cursor ->
            buildList { while (cursor.moveToNext()) add(JSONObject(cursor.getString(0))) }
        }
    private fun upsert(db: SQLiteDatabase, asset: JSONObject) {
        db.insertWithOnConflict("assets", null, ContentValues().apply {
            put("collection_id", asset.getString("collectionId")); put("id", asset.getString("id")); put("payload", asset.toString())
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }
    private fun scan(db: SQLiteDatabase, request: ScanRequest): List<String> {
        val id = request.id
        val collection = rows(db, "collections", "id=?", arrayOf(id)).firstOrNull() ?: error("Collection no longer exists.")
        val roots = collection.getJSONArray("roots")
        require(roots.length() > 0) { "Add a root folder before scanning." }
        val extensions = collection.getJSONArray("extensions").let { a -> (0 until a.length()).map { a.getString(it).lowercase() }.toSet() }
        val previous = rows(db, "assets", "collection_id=?", arrayOf(id)).associateBy { it.getString("id") }
        val found = linkedMapOf<String, JSONObject>()
        val configuredRoots = (0 until roots.length()).map { roots.getJSONObject(it).getString("uri") }.toSet()
        val warnings = mutableListOf<String>()
        val health = JSONObject()
        var lastProgress = 0L
        fun progress(folder: String) {
            val now = android.os.SystemClock.elapsedRealtime()
            if (now - lastProgress < 150) return
            lastProgress = now
            val count = found.size
            main.post { channel.invokeMethod("scanProgress", request.progress(count, folder)) }
        }
        fun checkCancelled() { if (cancelled.contains(id)) throw java.util.concurrent.CancellationException() }

        for (i in 0 until roots.length()) {
            val root = roots.getJSONObject(i)
            val tree = Uri.parse(root.getString("uri"))
            try {
                checkCancelled()
                val queue = java.util.ArrayDeque<Pair<String, String>>()
                val visited = mutableSetOf<String>()
                queue.add(DocumentsContract.getTreeDocumentId(tree) to "")
                while (queue.isNotEmpty()) {
                    checkCancelled()
                    val (parent, parentPath) = queue.removeFirst()
                    progress("${root.getString("name")}/$parentPath")
                    if (!visited.add(parent)) continue
                    val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
                    val cursor = resolver.query(children, arrayOf("document_id", "_display_name", "mime_type", "_size", "last_modified"), null, null, null) ?: error("Folder could not be read.")
                    cursor.use { c -> while (c.moveToNext()) {
                        checkCancelled()
                        val documentId = c.getString(0)
                        val filename = c.getString(1) ?: "Untitled video"
                        if (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) { queue.add(documentId to (parentPath + filename + "/")); continue }
                        if (filename.substringAfterLast('.', "").lowercase() !in extensions) continue
                        val key = "${tree.authority}:$documentId"
                        if (found.containsKey(key)) continue
                        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
                        val size = c.getLong(3); val modified = c.getLong(4)
                        val old = previous[key] ?: previous.values.singleOrNull {
                            val oldUri = runCatching { Uri.parse(it.optString("uri")) }.getOrNull()
                            oldUri?.authority == uri.authority && runCatching {
                                DocumentsContract.getDocumentId(oldUri)
                            }.getOrNull() == documentId
                        }
                        val stableKey = old?.getString("id") ?: key
                        if (found.containsKey(stableKey)) continue
                        val asset = old?.let { JSONObject(it.toString()) } ?: JSONObject().put("id", key).put("collectionId", id).put("positionMs", 0)
                        val contentType = if (collection.getString("subtype") == "videos") "videos" else root.optString("contentSubtype",
                            if (collection.getString("subtype") == "tv") "tv" else "movies")
                        require(contentType in listOf("videos", "movies", "tv"))
                        val previousType = old?.optString("contentSubtype", contentType) ?: contentType
                        if (previousType != contentType && previousType != "videos" && contentType != "videos") {
                            if (asset.optString("metadataSource", "filename") == "filename") asset.remove("metadata")
                            else {
                                asset.put("metadataStatus", "review")
                                warnings.add("$filename: folder content type changed; review this item's metadata.")
                            }
                        }
                        asset.put("id", stableKey).put("collectionId", id)
                        asset.put("rootUri", tree.toString()).put("relativePath", parentPath + filename).put("available", true)
                        asset.put("contentSubtype", contentType)
                        if (!asset.has("addedAt")) asset.put("addedAt", System.currentTimeMillis())
                        asset.put("uri", uri.toString()).put("filename", filename).put("size", size).put("modified", modified)
                        if (old == null || old.optLong("size") != size || old.optLong("modified") != modified ||
                            !java.io.File(asset.optString("thumbnail", "")).isFile) {
                            val retriever = MediaMetadataRetriever()
                            try {
                                retriever.setDataSource(context, uri)
                                asset.put("durationMs", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0)
                                asset.put("width", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0)
                                asset.put("height", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0)
                                try {
                                    val frame = if (android.os.Build.VERSION.SDK_INT >= 27) retriever.getScaledFrameAtTime(1000000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 640, 360)
                                        else retriever.getFrameAtTime(1000000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                    if (frame != null) {
                                        val folder = java.io.File(context.cacheDir, "video_thumbnails").apply { mkdirs() }
                                        val digest = java.security.MessageDigest.getInstance("SHA-256").digest("$key:$size:$modified".toByteArray()).joinToString("") { "%02x".format(it) }
                                        val image = java.io.File(folder, "$digest.jpg")
                                        try { image.outputStream().use { frame.compress(android.graphics.Bitmap.CompressFormat.JPEG, 82, it) }; asset.put("thumbnail", image.absolutePath) }
                                        finally { frame.recycle() }
                                    }
                                } catch (_: Exception) { /* Artwork is optional; indexing still succeeds. */ }
                            } catch (_: Exception) { /* Keep the file indexed even if a codec cannot be probed. */ }
                            finally { retriever.release() }
                        }
                        found[stableKey] = asset
                        progress("${root.getString("name")}/$parentPath")
                    } }
                }
                health.put(tree.toString(), "Available")
            } catch (_: java.util.concurrent.CancellationException) {
                cancelled.remove(id)
                return listOf("Scan cancelled. Previous index preserved.")
            } catch (_: Exception) {
                health.put(tree.toString(), "Unavailable — select this folder again")
                warnings.add("${root.getString("name")}: folder unavailable. Re-select it in collection settings.")
            }
        }
        if (cancelled.remove(id)) return listOf("Scan cancelled. Previous index preserved.")
        val reconnectedFrom = ScanIdentity.reconnect(previous, found, configuredRoots) { warnings.add(it) }
        val reconnected = reconnectedFrom.values.toSet()
        db.beginTransaction()
        try {
            val current = rows(db, "assets", "collection_id=?", arrayOf(id)).associateBy { it.getString("id") }
            // A partial/failed scan preserves the previous index rather than deleting inaccessible media.
            // Keep unavailable entries and their history so a reconnect can restore them.
            for ((key, old) in previous) if (key !in found) {
                val replacement = key in reconnected
                if (replacement) db.delete("assets", "collection_id=? AND id=?", arrayOf(id, key))
                else upsert(db, (current[key] ?: old).put("available", false))
            }
            // Reconnected assets retain their durable IDs, including queue references.
            collection.put("lastScanAt", System.currentTimeMillis()).put("rootHealth", health)
            db.update("collections", ContentValues().apply { put("payload", collection.toString()) }, "id=?", arrayOf(id))
            found.values.forEach { asset ->
                val latest = current[asset.getString("id")] ?: reconnectedFrom[asset.getString("id")]?.let { current[it] }
                if (latest != null) WatchProgress.copyHistory(latest, asset)
                upsert(db, asset)
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        return warnings
    }
    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (documents.onActivityResult(code, resultCode, data)) return true
        if (code != DocumentRequest.ROOT.code) return false
        val result = picker; picker = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) { result?.success(null); return true }
        try {
            val tree = data.data!!
            resolver.takePersistableUriPermission(tree, data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val document = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val name = resolver.query(document, arrayOf("_display_name"), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "Selected folder"
            result?.success(mapOf("uri" to tree.toString(), "name" to name))
        } catch (_: Exception) { result?.error("folder", "Could not retain access to this folder. Select it again.", null) }
        return true
    }
    private fun readingMime(format: String) = when (format) {
        "epub" -> "application/epub+zip"
        "txt" -> "text/plain"
        "pdf" -> "application/pdf"
        else -> error("Unsupported external reading format.")
    }
    fun close() { picker?.success(null); picker = null; executor.execute { readingComics.closeAll(); readingText.closeAll(); readingPdf.closeAll(); helper.close() }; executor.shutdown() }
    private fun map(value: JSONObject): Map<String, Any?> = value.keys().asSequence().associateWith { key -> convert(value.get(key)) }
    private fun convert(value: Any?): Any? = when (value) { JSONObject.NULL -> null; is JSONObject -> map(value); is JSONArray -> (0 until value.length()).map { convert(value.get(it)) }; else -> value }
}
