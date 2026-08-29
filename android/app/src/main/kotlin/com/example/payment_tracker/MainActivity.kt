package com.example.payment_tracker

import android.app.Activity
import android.content.Intent
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "payment_tracker/backup"
        private const val CREATE_BACKUP_REQUEST = 4101
        private const val OPEN_BACKUP_REQUEST = 4102
        private const val BACKUP_FORMAT = "payment_tracker_encrypted_backup"
        private const val BACKUP_VERSION = 1
        private const val PBKDF2_ITERATIONS = 310_000
    }

    private data class PendingCreate(
        val result: MethodChannel.Result,
        val content: String,
    )

    private var pendingCreate: PendingCreate? = null
    private var pendingOpenResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handleBackupCall(call, result) }
    }

    private fun handleBackupCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createEncryptedBackup" -> createEncryptedBackup(call, result)
            "chooseEncryptedBackup" -> chooseEncryptedBackup(result)
            "decryptBackup" -> decryptBackup(call, result)
            else -> result.notImplemented()
        }
    }

    private fun createEncryptedBackup(call: MethodCall, result: MethodChannel.Result) {
        if (pendingCreate != null || pendingOpenResult != null) {
            result.error("busy", "Another backup action is already in progress.", null)
            return
        }

        val payload = call.argument<String>("payload")
        val password = call.argument<String>("password")
        val suggestedName = call.argument<String>("suggestedName")
        if (payload.isNullOrEmpty() || password.isNullOrEmpty() || suggestedName.isNullOrEmpty()) {
            result.error("invalid_arguments", "Backup details are missing.", null)
            return
        }

        try {
            pendingCreate = PendingCreate(result, encrypt(payload, password))
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, suggestedName)
            }
            startActivityForResult(intent, CREATE_BACKUP_REQUEST)
        } catch (_: Exception) {
            pendingCreate = null
            result.error("encryption_failed", "Could not encrypt the backup.", null)
        }
    }

    private fun chooseEncryptedBackup(result: MethodChannel.Result) {
        if (pendingCreate != null || pendingOpenResult != null) {
            result.error("busy", "Another backup action is already in progress.", null)
            return
        }

        pendingOpenResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivityForResult(intent, OPEN_BACKUP_REQUEST)
        } catch (_: Exception) {
            pendingOpenResult = null
            result.error("picker_failed", "Could not open the document picker.", null)
        }
    }

    private fun decryptBackup(call: MethodCall, result: MethodChannel.Result) {
        val encryptedContent = call.argument<String>("encryptedContent")
        val password = call.argument<String>("password")
        if (encryptedContent.isNullOrEmpty() || password.isNullOrEmpty()) {
            result.error("invalid_arguments", "Backup details are missing.", null)
            return
        }

        try {
            result.success(decrypt(encryptedContent, password))
        } catch (_: Exception) {
            result.error("decryption_failed", "Wrong password or damaged backup file.", null)
        }
    }

    @Deprecated("Deprecated in Android SDK")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            CREATE_BACKUP_REQUEST -> finishCreateBackup(resultCode, data)
            OPEN_BACKUP_REQUEST -> finishOpenBackup(resultCode, data)
        }
    }

    private fun finishCreateBackup(resultCode: Int, data: Intent?) {
        val pending = pendingCreate ?: return
        pendingCreate = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.result.error("cancelled", "Backup save cancelled.", null)
            return
        }

        try {
            contentResolver.openOutputStream(uri)?.use { stream ->
                stream.write(pending.content.toByteArray(Charsets.UTF_8))
            } ?: throw IOException("Could not open selected file.")
            pending.result.success(null)
        } catch (_: Exception) {
            pending.result.error("write_failed", "Could not save the backup file.", null)
        }
    }

    private fun finishOpenBackup(resultCode: Int, data: Intent?) {
        val result = pendingOpenResult ?: return
        pendingOpenResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.error("cancelled", "Backup selection cancelled.", null)
            return
        }

        try {
            val content = contentResolver.openInputStream(uri)?.use { stream ->
                stream.readBytes().toString(Charsets.UTF_8)
            } ?: throw IOException("Could not open selected file.")
            result.success(content)
        } catch (_: Exception) {
            result.error("read_failed", "Could not read the backup file.", null)
        }
    }

    private fun encrypt(payload: String, password: String): String {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, passwordKey(password, salt), GCMParameterSpec(128, nonce))
        val ciphertext = cipher.doFinal(payload.toByteArray(Charsets.UTF_8))
        return JSONObject()
            .put("format", BACKUP_FORMAT)
            .put("format_version", BACKUP_VERSION)
            .put("kdf", "PBKDF2WithHmacSHA1")
            .put("iterations", PBKDF2_ITERATIONS)
            .put("salt", Base64.encodeToString(salt, Base64.NO_WRAP))
            .put("cipher", "AES-256-GCM")
            .put("nonce", Base64.encodeToString(nonce, Base64.NO_WRAP))
            .put("ciphertext", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            .toString()
    }

    private fun decrypt(encryptedContent: String, password: String): String {
        val envelope = JSONObject(encryptedContent)
        if (envelope.optString("format") != BACKUP_FORMAT ||
            envelope.optInt("format_version") != BACKUP_VERSION ||
            envelope.optString("kdf") != "PBKDF2WithHmacSHA1" ||
            envelope.optInt("iterations") != PBKDF2_ITERATIONS ||
            envelope.optString("cipher") != "AES-256-GCM") {
            throw IllegalArgumentException("Unsupported backup format.")
        }

        val salt = Base64.decode(envelope.getString("salt"), Base64.NO_WRAP)
        val nonce = Base64.decode(envelope.getString("nonce"), Base64.NO_WRAP)
        val ciphertext = Base64.decode(envelope.getString("ciphertext"), Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, passwordKey(password, salt), GCMParameterSpec(128, nonce))
        return cipher.doFinal(ciphertext).toString(Charsets.UTF_8)
    }

    private fun passwordKey(password: String, salt: ByteArray): SecretKeySpec {
        val keySpec = PBEKeySpec(password.toCharArray(), salt, PBKDF2_ITERATIONS, 256)
        return try {
            val key = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA1")
                .generateSecret(keySpec)
                .encoded
            SecretKeySpec(key, "AES")
        } finally {
            keySpec.clearPassword()
        }
    }
}
