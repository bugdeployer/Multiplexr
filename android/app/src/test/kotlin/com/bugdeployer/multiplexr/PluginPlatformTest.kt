package com.bugdeployer.multiplexr
import com.bugdeployer.multiplexr.plugins.*
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.net.InetAddress

class PluginPlatformTest {
    @Test fun expectedProviderDenialsAreValidRepliesInsteadOfQuarantineFailures() {
        for (code in listOf("permission_denied", "resource_limit", "deadline_exceeded")) {
            assertTrue(PluginReply.valid("""{"v":1,"id":"invoke","error":{"code":"$code"}}""", "invoke"))
        }
        for (raw in listOf("""{"v":1,"id":"invoke","error":{"code":"invented"}}""", """{"v":1,"id":"invoke","error":{"code":"permission_denied","secret":"no"}}""", """{"v":1,"id":"other","result":null}""")) {
            assertFalse(PluginReply.valid(raw, "invoke"))
        }
    }
    @Test fun atomicReplacementKeepsOnlyCompleteCommittedBytes() {
        val root=kotlin.io.path.createTempDirectory("plugin-atomic").toFile()
        try {
            val target=File(root,"state.json")
            repeat(20) { i -> PluginStore.atomic(target,"value-$i".toByteArray()); assertEquals("value-$i",target.readText()) }
            assertFalse(File(root,"state.json.pending").exists())
        } finally { root.deleteRecursively() }
    }
    @Test fun base64WorksWithoutApi26AndRejectsMalformedInputs() {
        for(n in 0..256) { val bytes=ByteArray(n) { it.toByte() }; assertArrayEquals(bytes,PluginEncoding.decode(PluginEncoding.encode(bytes))) }
        for(value in listOf("!", "a", "YW Jj", "====", "YQ=garbage")) denied { PluginEncoding.decode(value) }
        assertEquals("abc",String(PluginEncoding.decode("YWJj")))
    }
    private fun bytes(name: String) = javaClass.getResourceAsStream("/plugins/$name.json")!!.use { it.readBytes() }
    private fun denied(block: () -> Unit) { try { block(); fail("Expected rejection") } catch(_: Exception) {} }
    private fun activate(store: PluginStore,file: String) {
        val review=store.stage(bytes(file))
        store.activate(review["token"] as String,review["expected"] as Long,(review["permissions"] as List<*>).map { it as String }.toSet(),(review["origins"] as List<*>).map { it as String }.toSet(),setOf("collection"),false)
    }
    @Test fun sessionCommandsAreTimeOnlyBoundedAndStrict() {
        assertEquals(listOf(PluginSessionCommand("pause"),PluginSessionCommand("seek",2500)), PluginSessionPolicy.commands(JSONArray("[{\"kind\":\"pause\"},{\"kind\":\"seek\",\"position\":{\"kind\":\"time\",\"milliseconds\":2500}}]")))
        for(raw in listOf("[{\"kind\":\"stop\"}]", "[{\"kind\":\"pause\",\"extra\":1}]", "[{\"kind\":\"seek\",\"position\":{\"kind\":\"time\",\"milliseconds\":-1}}]", "[{\"kind\":\"seek\",\"position\":{\"kind\":\"page\",\"index\":1}}]")) denied { PluginSessionPolicy.commands(JSONArray(raw)) }
        denied { PluginSessionPolicy.commands(JSONArray().apply { repeat(9) { put(JSONObject().put("kind","pause")) } }) }
    }
    @Test fun failedSettingsMigrationKeepsActivePackageAndGrants() {
        val root=kotlin.io.path.createTempDirectory("plugin-migration").toFile()
        try {
            val store=PluginStore(root,prepareSettings={ p -> require(p.version=="1.0.0") })
            activate(store,"installed-v1");val before=store.row("org.example.installed").toString()
            denied { activate(store,"installed-v2") }
            assertEquals(before,store.row("org.example.installed").toString())
        } finally { root.deleteRecursively() }
    }
    @Test fun restoredInventorySurvivesExportWithoutInstallingCode() {
        val root=kotlin.io.path.createTempDirectory("plugin-portable").toFile()
        try {
            val p=PluginPackage.parse(bytes("installed-v1"))
            val restored=JSONObject().put("version",1).put("inventory",JSONArray().put(JSONObject().put("id",p.id).put("version",p.version).put("publisher",p.publisher)))
            val merged=PluginPortable.merge(PluginPortable.read(root),restored)
            assertEquals(1,merged.getJSONArray("inventory").length())
            assertTrue(PluginStore(root).inventory().isEmpty())
        } finally { root.deleteRecursively() }
    }
    @Test fun duplicateEnvelopeAndTrailingJsonAreRejected() {
        val raw=String(bytes("installed-v1"),Charsets.UTF_8)
        denied { PluginPackage.parse((raw+"{}").toByteArray()) }
        denied { PluginPackage.parse(raw.replaceFirst("{","{\"format\":\"multiplexr-plugin-1\",").toByteArray()) }
    }
    @Test fun independentlySignedFixtureVerifies() { val p=PluginPackage.parse(bytes("installed-v1"));assertEquals("org.example.installed",p.id);assertEquals("1.0.0",p.version);assertEquals(setOf("https://example.com"),p.origins) }
    @Test fun signedPayloadTamperingIsRejected() {
        for(field in listOf("payload","publicKey","signature")) { val doc=JSONObject(String(bytes("installed-v1")));doc.put(field,"AAAA");try { PluginPackage.parse(doc.toString().toByteArray());fail("Expected rejection") } catch(_: Exception) {} }
        denied { PluginPackage.parse(ByteArray(PluginPackage.MAX_BYTES+1)) }
    }
    @Test fun installsDisabledAndPreventsReplayAndUnreviewedKeyChanges() {
        val root=kotlin.io.path.createTempDirectory("plugin-test").toFile()
        try {
            val store=PluginStore(root);activate(store,"installed-v1");val id="org.example.installed"
            assertFalse(store.row(id).getBoolean("enabled"));val rev=store.row(id).getLong("revision")
            denied { store.packageFor(id,rev) };store.enabled(id,true)
            denied { store.packageFor(id,rev) };val current=store.row(id).getLong("revision");store.packageFor(id,current)
            val changed=store.stage(bytes("substituted-v3"));assertEquals(true,changed["publisherChanged"])
            denied { store.activate(changed["token"] as String,current,setOf("runtime.ping"),emptySet(),emptySet(),false) }
            denied { store.stage(bytes("installed-v1")) }
            assertEquals("1.0.0",store.summary(id)["version"])
        } finally { root.deleteRecursively() }
    }
    @Test fun badUpdateAndStagingInterruptionKeepLastWorkingPackage() {
        val root=kotlin.io.path.createTempDirectory("plugin-update").toFile()
        try {
            var store=PluginStore(root);activate(store,"installed-v1");val id="org.example.installed";store.enabled(id,true);store.success(id,store.row(id).getLong("revision"))
            val stage=store.stage(bytes("installed-v2"));store=PluginStore(root)
            denied { store.activate(stage["token"] as String,2,setOf("runtime.ping"),emptySet(),emptySet(),false) }
            assertEquals("1.0.0",store.summary(id)["version"])
            activate(store,"installed-v2");assertFalse(store.row(id).getBoolean("enabled"))
            File(root,"packages/"+store.row(id).getString("active")).writeText("corrupted")
            assertEquals(false,store.summary(id)["enabled"])
            store.rollback(id);assertEquals("1.0.0",store.summary(id)["version"]);assertFalse(store.row(id).getBoolean("enabled"))
        } finally { root.deleteRecursively() }
    }
    @Test fun permissionRevocationInvalidatesEpochAndDisablesPackage() {
        val root=kotlin.io.path.createTempDirectory("plugin-grant").toFile()
        try { val store=PluginStore(root);activate(store,"installed-v1");val id="org.example.installed";store.enabled(id,true);val rev=store.row(id).getLong("revision");store.permissions(id,rev,emptySet(),emptySet(),emptySet());denied { store.packageFor(id,rev) };denied { store.enabled(id,true) } } finally { root.deleteRecursively() }
    }
    @Test fun privateStorageIsNamespacedBoundedAndRemovalKeepsLibrarySeparate() {
        val root=kotlin.io.path.createTempDirectory("plugin-data").toFile()
        try { val store=PluginStore(root);activate(store,"installed-v1");val id="org.example.installed";store.privateWrite(id,1,"value","retained");assertNull(store.privateRead("org.other.tool",1,"value"));denied { store.privateWrite(id,1,"../escape","x") };denied { store.privateWrite(id,1,"big","x".repeat(32769)) };store.remove(id,false);assertEquals("retained",store.privateRead(id,1,"value")) } finally { root.deleteRecursively() }
    }
    @Test fun repeatedFailuresAndUncleanStartupDisableWithoutExecutingCode() {
        val root=kotlin.io.path.createTempDirectory("plugin-recovery").toFile()
        try { var store=PluginStore(root);activate(store,"installed-v1");val id="org.example.installed";store.enabled(id,true);repeat(3) { store.failure(id) };assertFalse(store.row(id).getBoolean("enabled"));store.enabled(id,true);store.startInvocation();store=PluginStore(root);assertFalse(store.row(id).getBoolean("enabled")) } finally { root.deleteRecursively() }
    }
    @Test fun networkRejectsPrivateAndTransitionDestinations() {
        for(ip in listOf("127.0.0.1","10.0.0.1","172.16.0.1","192.168.0.1","169.254.169.254","100.64.0.1","0.0.0.0","::1","fe80::1","fc00::1","2002:7f00:1::1")) assertFalse(ip,PluginNetworkPolicy.publicAddress(InetAddress.getByName(ip)))
        assertTrue(PluginNetworkPolicy.publicAddress(InetAddress.getByName("8.8.8.8")))
        for(url in listOf("http://example.com","https://example.com:8443","https://user:pass@example.com","https://unapproved.example")) denied { PluginNetworkPolicy.url(url,setOf("https://example.com")) }
    }
    @Test fun portableInventoryCannotRestoreCodeSecretsOrGrants() {
        val p=PluginPackage.parse(bytes("installed-v1"));val doc=JSONObject().put("version",1).put("inventory",JSONArray().put(JSONObject().put("id",p.id).put("version",p.version).put("publisher",p.publisher)))
        PluginPortable.validate(doc)
        for(key in listOf("code","enabled","permissions","secret","url")) denied { PluginPortable.validate(JSONObject(doc.toString()).put(key,"bad")) }
    }
}
