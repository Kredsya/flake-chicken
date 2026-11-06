package dev.flakechicken.flake_chicken

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.Signature
import java.security.spec.ECGenParameterSpec

object InstallationIdentity {
    private const val alias = "flake-chicken-installation-v1"
    private fun keyStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    @Synchronized
    fun identity(context: Context): Map<String, String> {
        val prefs = context.getSharedPreferences("installation_identity", Context.MODE_PRIVATE)
        val store = keyStore()
        var salt = prefs.getString("salt", null)
        if (salt == null || !store.containsAlias(alias)) {
            if (store.containsAlias(alias)) store.deleteEntry(alias)
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256).build())
                generateKeyPair()
            }
            salt = Base64.encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) }, Base64.NO_WRAP)
            check(prefs.edit().putString("salt", salt).commit()) { "Could not persist identity" }
        }
        val publicKey = store.getCertificate(alias).publicKey.encoded
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update("flake-chicken-identity-v1\u0000".toByteArray(Charsets.UTF_8))
        digest.update(Base64.decode(salt, Base64.NO_WRAP))
        digest.update(publicKey)
        return mapOf("uid" to digest.digest().joinToString("") { "%02x".format(it) },
            "salt" to salt, "publicKey" to Base64.encodeToString(publicKey, Base64.NO_WRAP), "platform" to "android")
    }
    @Synchronized
    fun sign(payload: String): String {
        val privateKey = keyStore().getKey(alias, null) as java.security.PrivateKey
        return Base64.encodeToString(Signature.getInstance("SHA256withECDSA").run {
            initSign(privateKey); update(payload.toByteArray(Charsets.UTF_8)); sign()
        }, Base64.NO_WRAP)
    }
}
