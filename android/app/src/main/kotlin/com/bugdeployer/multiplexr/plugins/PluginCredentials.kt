package com.bugdeployer.multiplexr.plugins

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Host-only credential templates. Scripts receive no secret bytes. */
internal class PluginCredentials(private val root: File) {
    private val alias = "multiplexr.plugins.credentials.v1"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun file(id: String, origin: String) = File(root, PluginPackage.sha((id + "\n" + origin).toByteArray(Charsets.UTF_8)))
    @Synchronized fun save(id: String, origin: String, secret: String?) {
        PluginPackage.origin(origin); val target = file(id, origin)
        if(secret == null || secret.isEmpty()) { target.delete(); return }
        require(secret.length <= 4096 && secret.none { it == '\r' || it == '\n' })
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()); updateAAD((id + origin).toByteArray(Charsets.UTF_8)) }
        val encrypted = cipher.doFinal(secret.toByteArray(Charsets.UTF_8)); PluginStore.atomic(target, cipher.iv + encrypted)
    }
    @Synchronized fun header(id: String, origin: String): Pair<String,String>? {
        val f = file(id, origin); if(!f.exists()) return null
        val bytes = f.readBytes(); require(bytes.size in 29..8192)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0,12))); updateAAD((id + origin).toByteArray(Charsets.UTF_8)) }
        return "Authorization" to "Bearer " + String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
    }
    @Synchronized fun remove(id: String, origins: Set<String>) { origins.forEach { file(id,it).delete() } }
}
