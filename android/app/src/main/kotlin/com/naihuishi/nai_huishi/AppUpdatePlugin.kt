package com.naihuishi.nai_huishi

import android.app.Activity
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.net.URI
import java.security.MessageDigest
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.zip.ZipFile

/** A public no-argument subclass avoids FileProvider base-class manifest compatibility issues. */
class AppUpdateFileProvider : FileProvider()

/** The system owns downloads; this plugin owns validation and the installation hand-off. */
class AppUpdatePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var activity: Activity? = null
    @Volatile private var attached = false
    private var checkedOrphans = false

    private val preferences get() = context.getSharedPreferences("app_update_v1", Context.MODE_PRIVATE)
    private val downloads get() = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        attached = true
        channel = MethodChannel(binding.binaryMessenger, "worldpainter/app_update")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        channel.setMethodCallHandler(null)
        activity = null
        worker.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onDetachedFromActivity() { activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in METHODS) {
            result.notImplemented()
            return
        }
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "getInstalledInfo" -> installedInfo()
                    "startDownload" -> startDownload(call.argument<Any>("manifest")).toMap()
                    "getDownloadState" -> refreshState().toMap()
                    "cancelDownload" -> cancelDownload().toMap()
                    "verifyDownload" -> verifyDownload().toMap()
                    "canInstallPackages" -> canInstallPackages()
                    "openInstallPermission" -> { openInstallPermission(); null }
                    "installUpdate" -> { installUpdate(); null }
                    "openReleasePage" -> { openReleasePage(call.argument<Any>("url")); null }
                    else -> null
                }
                reply { result.success(value) }
            } catch (error: UpdateException) {
                reply { result.error(error.code, error.message, null) }
            } catch (_: Exception) {
                // Platform exceptions may contain request URLs or file paths. Never forward them.
                reply { result.error("NATIVE_UPDATE_FAILED", "更新操作失败，请重试或前往官方发布页。", null) }
            }
        }
    }

    private fun reply(block: () -> Unit) {
        main.post { if (attached) block() }
    }

    private fun <T> onMain(block: () -> T): T {
        val task = FutureTask(block)
        main.post(task)
        try {
            return task.get()
        } catch (error: ExecutionException) {
            throw (error.cause as? Exception ?: UpdateException("NATIVE_UPDATE_FAILED", "无法打开系统页面。"))
        }
    }

    @Suppress("DEPRECATION")
    private fun packageInfo(): PackageInfo = context.packageManager.getPackageInfo(context.packageName, signatureFlags())

    private fun signatureFlags(): Int = if (Build.VERSION.SDK_INT >= 28) {
        PackageManager.GET_SIGNING_CERTIFICATES
    } else {
        @Suppress("DEPRECATION")
        PackageManager.GET_SIGNATURES
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signerHashes(info: PackageInfo): Set<String> {
        // V1 deliberately requires the same current signers; certificate rotation is not enabled.
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { AppUpdateRules.sha256(it.toByteArray()) }?.toSet() ?: emptySet()
    }

    private fun installedInfo(): Map<String, Any> {
        val info = packageInfo()
        return mapOf(
            "packageName" to context.packageName,
            "versionName" to (info.versionName ?: ""),
            "versionCode" to versionCode(info),
            "sdkInt" to Build.VERSION.SDK_INT,
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
            "signerSha256" to signerHashes(info).sorted(),
        )
    }

    private fun requireOfficialBuild(info: PackageInfo = packageInfo()) {
        if (context.packageName != AppUpdateRules.PACKAGE_NAME || !AppUpdateRules.isStableVersion(info.versionName ?: "")) {
            throw UpdateException("PREVIEW_NOT_SUPPORTED", "测试版不支持正式版自动更新，请前往官方发布页。")
        }
    }

    private fun requireEligible(manifest: UpdateManifest) {
        val installed = packageInfo()
        requireOfficialBuild(installed)
        AppUpdateRules.requireEligible(manifest, context.packageName, versionCode(installed), Build.VERSION.SDK_INT, Build.SUPPORTED_ABIS.toList())
    }

    private fun updateFile(): File {
        val base = context.getExternalFilesDir(null)
            ?: throw UpdateException("UPDATE_STORAGE_UNAVAILABLE", "更新缓存目录不可用，请检查存储空间。")
        val directory = File(base, "updates")
        if ((!directory.isDirectory && !directory.mkdirs()) || directory.canonicalFile.parentFile != base.canonicalFile) {
            throw UpdateException("UPDATE_STORAGE_UNAVAILABLE", "更新缓存目录不可用。")
        }
        return File(directory, "app-release.apk").also {
            if (it.canonicalFile != File(directory.canonicalFile, "app-release.apk")) throw UpdateException("UPDATE_STORAGE_UNAVAILABLE", "更新缓存文件路径异常。")
        }
    }

    private fun startDownload(arguments: Any?): UpdateRecord {
        val manifest = AppUpdateRules.parseManifest(arguments)
        requireEligible(manifest)
        val previous = refreshState()
        if (previous.status !in setOf("none", "failed")) {
            if (previous.manifest == manifest) return previous
            throw UpdateException("DOWNLOAD_ACTIVE", "已有更新任务，请先取消当前下载。")
        }
        cleanup(previous)
        val file = updateFile()
        if (file.exists()) throw UpdateException("UPDATE_STORAGE_UNAVAILABLE", "无法清理旧的更新缓存。")
        val request = DownloadManager.Request(Uri.parse(manifest.apkUrl))
            .setTitle("NAI 绘世 ${manifest.versionName}")
            .setDescription("正在下载官方更新，完成后将在应用内校验。")
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setDestinationInExternalFilesDir(context, null, "updates/app-release.apk")
        val id = try {
            downloads.enqueue(request)
        } catch (_: Exception) {
            throw UpdateException("DOWNLOAD_START_FAILED", "无法创建系统下载任务，请检查网络和存储空间。")
        }
        val record = UpdateRecord(manifest, id, "pending", totalBytes = manifest.sizeBytes)
        try {
            saveRecord(record)
        } catch (error: Exception) {
            cleanup(record)
            throw error
        }
        return record
    }

    private fun refreshState(): UpdateRecord {
        val record = loadRecord() ?: run {
            cleanupOrphans()
            return UpdateRecord()
        }
        val manifest = record.manifest ?: return record
        if (context.packageName == manifest.packageName && versionCode(packageInfo()) >= manifest.versionCode) {
            cleanup(record)
            clearRecord()
            return UpdateRecord()
        }
        if (record.status == "failed") return record
        try {
            requireEligible(manifest)
            if (record.downloadId <= 0) return fail(record, "系统下载任务已丢失，请重新下载。")
            val cursor = downloads.query(DownloadManager.Query().setFilterById(record.downloadId))
                ?: return fail(record, "无法读取系统下载任务，请重新下载。")
            cursor.use {
                if (!it.moveToFirst()) return fail(record, "系统下载任务已丢失，请重新下载。")
                val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val received = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)).coerceAtLeast(0)
                val total = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                val systemStatus = when (status) {
                    DownloadManager.STATUS_PENDING -> "pending"
                    DownloadManager.STATUS_RUNNING -> "running"
                    DownloadManager.STATUS_PAUSED -> "paused"
                    DownloadManager.STATUS_SUCCESSFUL -> "successful"
                    DownloadManager.STATUS_FAILED -> "failed"
                    else -> "unknown"
                }
                val fileSize = if (systemStatus == "successful") updateFile().takeIf { file -> file.isFile }?.length() else null
                return AppUpdateRules.reconcileDownload(record, systemStatus, received, total, fileSize).also(::saveRecord)
            }
        } catch (error: UpdateException) {
            return fail(record, error.message)
        } catch (_: Exception) {
            return fail(record, "无法恢复更新任务，请重新下载。")
        }
    }

    private fun cancelDownload(): UpdateRecord {
        val record = loadRecord() ?: UpdateRecord()
        return try {
            cleanup(record)
            cleanupOrphans()
            clearRecord()
            UpdateRecord()
        } catch (_: Exception) {
            fail(record, "暂时无法清理更新缓存，请重试取消。")
        }
    }

    private fun verifyDownload(): UpdateRecord {
        val record = refreshState()
        if (record.status !in setOf("downloaded", "ready", "awaitingInstall")) {
            if (record.status == "failed" || record.status == "none") return record
            throw UpdateException("DOWNLOAD_NOT_READY", "更新尚未下载完成。")
        }
        val manifest = record.manifest ?: return fail(record, "更新清单已丢失，请重新下载。")
        return try {
            requireEligible(manifest)
            val file = updateFile()
            if (!file.isFile) throw UpdateException("VERIFY_FAILED", "更新文件已丢失，请重新下载。")
            file.inputStream().buffered().use { AppUpdateRules.verifyStream(it, manifest.sizeBytes, manifest.sha256) }
            @Suppress("DEPRECATION")
            val archive = context.packageManager.getPackageArchiveInfo(file.absolutePath, signatureFlags())
                ?: throw UpdateException("VERIFY_FAILED", "无法解析或验证更新安装包。")
            val appInfo = archive.applicationInfo
                ?: throw UpdateException("VERIFY_FAILED", "更新安装包信息不完整。")
            if (archive.packageName != manifest.packageName || archive.packageName != context.packageName ||
                versionCode(archive) != manifest.versionCode || archive.versionName != manifest.versionName ||
                !AppUpdateRules.isStableVersion(archive.versionName ?: "") || appInfo.minSdkVersion != manifest.minSdk ||
                appInfo.minSdkVersion > Build.VERSION.SDK_INT) {
                throw UpdateException("VERIFY_FAILED", "更新安装包与官方清单或当前设备不匹配。")
            }
            AppUpdateRules.verifyNativeLibraries(file, manifest.abi)
            if (!AppUpdateRules.sameSigners(signerHashes(packageInfo()), signerHashes(archive))) {
                throw UpdateException("SIGNATURE_MISMATCH", "更新安装包签名与当前应用不一致，已拒绝安装。")
            }
            record.copy(status = "ready", downloadedBytes = manifest.sizeBytes, totalBytes = manifest.sizeBytes, reason = null).also(::saveRecord)
        } catch (error: UpdateException) {
            fail(record, error.message)
        } catch (_: Exception) {
            fail(record, "更新文件校验失败，请重新下载。")
        }
    }

    private fun canInstallPackages(): Boolean = Build.VERSION.SDK_INT < 26 || context.packageManager.canRequestPackageInstalls()

    private fun openInstallPermission() {
        requireOfficialBuild()
        onMain {
            val current = requireActivity()
            val intent = if (Build.VERSION.SDK_INT >= 26) {
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
            } else {
                Intent(Settings.ACTION_SECURITY_SETTINGS)
            }
            try {
                current.startActivity(intent)
            } catch (_: Exception) {
                throw UpdateException("INSTALL_PERMISSION_UNAVAILABLE", "无法打开安装权限设置，请在系统设置中允许此应用安装更新。")
            }
        }
        // Returning from settings never launches installation automatically.
    }

    private fun installUpdate() {
        requireOfficialBuild()
        if (!canInstallPackages()) throw UpdateException("INSTALL_PERMISSION_REQUIRED", "请先允许此应用安装更新，再次点击安装。")
        // Re-hash and re-parse on every explicit install; persisted ready is not a trust boundary.
        val record = verifyDownload()
        if (record.status != "ready") throw UpdateException("VERIFY_FAILED", record.reason ?: "没有可安装的更新，请重新检查更新。")
        onMain {
            if (!canInstallPackages()) throw UpdateException("INSTALL_PERMISSION_REQUIRED", "请先允许此应用安装更新，再次点击安装。")
            val current = requireActivity()
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.app_update_files", updateFile())
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                clipData = ClipData.newRawUri("NAI 绘世更新", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            try {
                current.startActivity(intent)
            } catch (_: ActivityNotFoundException) {
                throw UpdateException("INSTALLER_UNAVAILABLE", "未找到系统安装器，请前往官方发布页手动安装。")
            } catch (_: SecurityException) {
                throw UpdateException("INSTALL_LAUNCH_FAILED", "系统拒绝打开安装器，请检查安装权限后重试。")
            }
        }
        // Launching an installer does not prove installation. The next app start checks installed code.
        saveRecord(record.copy(status = "awaitingInstall"))
    }

    private fun openReleasePage(argument: Any?) {
        val url = if (argument == null) AppUpdateRules.RELEASES_URL else {
            if (argument !is String) throw UpdateException("INVALID_URL", "官方发布页地址无效。")
            try {
                AppUpdateRules.requireReleaseUrl(argument, allowIndex = true)
            } catch (_: UpdateException) {
                throw UpdateException("INVALID_URL", "官方发布页地址无效。")
            }
            argument
        }
        onMain {
            try {
                requireActivity().startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE))
            } catch (_: ActivityNotFoundException) {
                throw UpdateException("NO_BROWSER", "未找到可用浏览器。")
            } catch (_: SecurityException) {
                throw UpdateException("OPEN_RELEASE_FAILED", "无法打开官方发布页。")
            }
        }
    }

    private fun requireActivity(): Activity = activity?.takeUnless { it.isFinishing || it.isDestroyed }
        ?: throw UpdateException("ACTIVITY_UNAVAILABLE", "应用界面尚未就绪，请稍后重试。")

    private fun cleanup(record: UpdateRecord) {
        if (record.downloadId > 0) downloads.remove(record.downloadId)
        val file = updateFile()
        try {
            context.revokeUriPermission(FileProvider.getUriForFile(context, "${context.packageName}.app_update_files", file), Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) { /* No grant exists before an installation hand-off. */ }
        if (file.exists() && !file.delete()) throw UpdateException("UPDATE_CLEANUP_FAILED", "无法清理更新缓存，请重试。")
    }

    private fun cleanupOrphans() {
        if (checkedOrphans) return
        val file = updateFile()
        val localUri = Uri.fromFile(file).toString()
        val ids = mutableListOf<Long>()
        downloads.query(DownloadManager.Query())?.use { cursor ->
            val uriColumn = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
            val idColumn = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)
            while (cursor.moveToNext()) {
                if (cursor.getString(uriColumn) == localUri) ids.add(cursor.getLong(idColumn))
            }
        }
        if (ids.isNotEmpty()) downloads.remove(*ids.toLongArray())
        if (file.exists() && !file.delete()) throw UpdateException("UPDATE_CLEANUP_FAILED", "无法清理旧的更新缓存。")
        checkedOrphans = true
    }

    private fun fail(record: UpdateRecord, reason: String): UpdateRecord {
        val cleaned = try { cleanup(record); true } catch (_: Exception) { false }
        return record.copy(status = "failed", reason = reason, downloadedBytes = 0,
            downloadId = if (cleaned) -1 else record.downloadId).also(::saveRecord)
    }

    private fun saveRecord(record: UpdateRecord) {
        val json = JSONObject().apply {
            put("manifest", record.manifest?.let { JSONObject(it.toMap()) } ?: JSONObject.NULL)
            put("downloadId", record.downloadId)
            put("status", record.status)
            put("downloadedBytes", record.downloadedBytes)
            put("totalBytes", record.totalBytes)
            put("reason", record.reason ?: JSONObject.NULL)
        }
        if (!preferences.edit().putString("record", json.toString()).commit()) {
            throw UpdateException("UPDATE_STATE_FAILED", "无法保存更新任务，请检查存储空间。")
        }
    }

    private fun clearRecord() {
        if (!preferences.edit().remove("record").commit()) throw UpdateException("UPDATE_STATE_FAILED", "无法清理更新任务记录。")
    }

    private fun loadRecord(): UpdateRecord? {
        val raw = preferences.getString("record", null) ?: return null
        return try {
            val json = JSONObject(raw)
            val status = json.getString("status")
            if (status !in PERSISTED_STATUSES) throw IllegalArgumentException()
            val manifest = json.optJSONObject("manifest")?.let { AppUpdateRules.parseManifest(jsonToMap(it)) }
            if (manifest == null && status != "failed") throw IllegalArgumentException()
            UpdateRecord(manifest, json.getLong("downloadId"), status,
                json.getLong("downloadedBytes").coerceAtLeast(0), manifest?.sizeBytes ?: 0,
                if (json.isNull("reason")) null else json.getString("reason"))
        } catch (_: Exception) {
            val id = try { JSONObject(raw).optLong("downloadId", -1) } catch (_: Exception) { -1 }
            fail(UpdateRecord(downloadId = id), "更新任务记录已损坏，请重新下载。")
        }
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { key ->
        when (val value = json.get(key)) {
            JSONObject.NULL -> null
            is JSONObject -> jsonToMap(value)
            is JSONArray -> throw IllegalArgumentException()
            else -> value
        }
    }

    companion object {
        private val METHODS = setOf("getInstalledInfo", "startDownload", "getDownloadState", "cancelDownload", "verifyDownload", "canInstallPackages", "openInstallPermission", "installUpdate", "openReleasePage")
        private val PERSISTED_STATUSES = setOf("pending", "running", "paused", "downloaded", "ready", "failed", "awaitingInstall")
    }
}

internal class UpdateException(val code: String, override val message: String) : Exception(message)

internal data class UpdateRecord(
    val manifest: UpdateManifest? = null,
    val downloadId: Long = -1,
    val status: String = "none",
    val downloadedBytes: Long = 0,
    val totalBytes: Long = 0,
    val reason: String? = null,
) {
    fun toMap(): Map<String, Any> = mutableMapOf<String, Any>("status" to status, "downloadedBytes" to downloadedBytes, "totalBytes" to totalBytes).apply {
        manifest?.let { put("manifest", it.toMap()) }
        reason?.let { put("reason", it) }
    }
}

internal data class UpdateManifest(
    val packageName: String,
    val versionName: String,
    val versionCode: Long,
    val publishedAt: String,
    val releaseNotes: String,
    val releaseUrl: String,
    val apkUrl: String,
    val sizeBytes: Long,
    val sha256: String,
    val abi: String,
    val minSdk: Int,
) {
    fun toMap(): Map<String, Any> = mapOf("schemaVersion" to 1, "channel" to "stable", "packageName" to packageName,
        "versionName" to versionName, "versionCode" to versionCode, "publishedAt" to publishedAt, "releaseNotes" to releaseNotes,
        "releaseUrl" to releaseUrl, "apk" to mapOf("url" to apkUrl, "sizeBytes" to sizeBytes, "sha256" to sha256, "abi" to abi, "minSdk" to minSdk))
}

/** Pure JVM rules are kept testable without an Android device or network requests. */
internal object AppUpdateRules {
    const val PACKAGE_NAME = "com.naihuishi.nai_huishi"
    const val RELEASES_URL = "https://github.com/sakiko0901/NAI-WorldPainter/releases"
    private const val RELEASE_PATH = "/sakiko0901/NAI-WorldPainter/releases"
    private val stableVersion = Regex("[0-9]+\\.[0-9]+\\.[0-9]+(?:\\.[0-9]+)?")
    private val safeTag = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
    private val prereleaseTag = Regex("(^|[-._])(preview|alpha|beta|rc|dev|canary|test)([-._0-9]|$)", RegexOption.IGNORE_CASE)

    fun isStableVersion(value: String): Boolean = value.length <= 64 && stableVersion.matches(value)

    fun parseManifest(argument: Any?): UpdateManifest {
        val map = argument as? Map<*, *> ?: invalid()
        val apk = map["apk"] as? Map<*, *> ?: invalid()
        if (map.keys != setOf("schemaVersion", "channel", "packageName", "versionName", "versionCode", "publishedAt", "releaseNotes", "releaseUrl", "apk") ||
            apk.keys != setOf("url", "sizeBytes", "sha256", "abi", "minSdk")) invalid()
        if (integer(map["schemaVersion"]) != 1L || map["channel"] != "stable" || map["packageName"] != PACKAGE_NAME) invalid()
        val versionName = string(map["versionName"])
        if (!isStableVersion(versionName)) invalid()
        val code = integer(map["versionCode"])
        val size = integer(apk["sizeBytes"])
        val minSdk = integer(apk["minSdk"])
        if (code !in 1..Int.MAX_VALUE.toLong() || size !in 1..(512L * 1024 * 1024) || minSdk !in 21L..100L) invalid()
        val releaseUrl = string(map["releaseUrl"])
        val tag = requireReleaseUrl(releaseUrl)
        val apkUrl = string(apk["url"])
        if (trustedUri(apkUrl).rawPath != "$RELEASE_PATH/download/$tag/app-release.apk") invalid()
        val hash = string(apk["sha256"])
        if (!Regex("[0-9a-fA-F]{64}").matches(hash) || apk["abi"] != "arm64-v8a") invalid()
        val published = string(map["publishedAt"])
        if (!isIsoDate(published)) invalid()
        val notes = map["releaseNotes"] as? String ?: invalid()
        if (notes.length > 64 * 1024 || Regex("[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]").containsMatchIn(notes)) invalid()
        return UpdateManifest(PACKAGE_NAME, versionName, code, published, notes, releaseUrl, apkUrl, size, hash.lowercase(Locale.ROOT), "arm64-v8a", minSdk.toInt())
    }

    fun requireReleaseUrl(url: String, allowIndex: Boolean = false): String {
        val path = trustedUri(url).rawPath
        if (allowIndex && path in setOf(RELEASE_PATH, "$RELEASE_PATH/latest")) return ""
        val tag = path?.takeIf { it.startsWith("$RELEASE_PATH/tag/") }?.removePrefix("$RELEASE_PATH/tag/") ?: invalid()
        if (!safeTag.matches(tag) || prereleaseTag.containsMatchIn(tag)) invalid()
        return tag
    }

    private fun trustedUri(url: String): URI {
        val uri = try { URI(url) } catch (_: Exception) { invalid() }
        if (uri.scheme != "https" || uri.rawAuthority != "github.com" || uri.host != "github.com" || uri.rawUserInfo != null ||
            uri.port != -1 || uri.rawQuery != null || uri.rawFragment != null || uri.isOpaque || url.length > 512) invalid()
        return uri
    }

    private fun isIsoDate(value: String): Boolean {
        val matched = Regex("([0-9]{4})-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})").matchEntire(value) ?: return false
        if (matched.groupValues[1].toInt() < 1970) return false
        val zone = matched.groupValues[2]
        if (zone != "Z") {
            val hours = zone.substring(1, 3).toInt()
            val minutes = zone.substring(4, 6).toInt()
            if (hours > 14 || minutes > 59 || (hours == 14 && minutes != 0)) return false
        }
        val seconds = value.replace(Regex("\\.[0-9]+(?=Z|[+-])"), "")
        val position = ParsePosition(0)
        return SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply { isLenient = false }.parse(seconds, position) != null && position.index == seconds.length
    }

    fun requireEligible(manifest: UpdateManifest, installedPackage: String, installedCode: Long, sdk: Int, abis: List<String>) {
        if (installedPackage != PACKAGE_NAME || manifest.packageName != installedPackage) throw UpdateException("PACKAGE_MISMATCH", "更新包与当前应用不匹配。")
        if (manifest.versionCode <= installedCode) throw UpdateException("NOT_NEWER", "此更新版本不高于当前版本。")
        if (manifest.minSdk > sdk) throw UpdateException("SDK_UNSUPPORTED", "此更新不支持当前 Android 版本。")
        if (manifest.abi != "arm64-v8a" || manifest.abi !in abis) throw UpdateException("ABI_UNSUPPORTED", "此更新仅支持 arm64 设备。")
    }

    fun reconcileDownload(record: UpdateRecord, systemStatus: String?, received: Long, total: Long, fileSize: Long?): UpdateRecord {
        val manifest = record.manifest ?: throw UpdateException("DOWNLOAD_STATE_FAILED", "更新清单已丢失，请重新下载。")
        if (systemStatus == null) throw UpdateException("DOWNLOAD_STATE_FAILED", "系统下载任务已丢失，请重新下载。")
        if (received > manifest.sizeBytes || (total > 0 && total != manifest.sizeBytes)) {
            throw UpdateException("DOWNLOAD_STATE_FAILED", "下载文件大小与官方清单不一致，请重新下载。")
        }
        val status = when (systemStatus) {
            "pending", "running", "paused" -> {
                if (record.status in setOf("downloaded", "ready", "awaitingInstall")) {
                    throw UpdateException("DOWNLOAD_STATE_FAILED", "系统下载状态已变化，请重新下载。")
                }
                systemStatus
            }
            "successful" -> {
                if (fileSize != manifest.sizeBytes) throw UpdateException("DOWNLOAD_STATE_FAILED", "更新文件缺失或大小不正确，请重新下载。")
                if (record.status in setOf("ready", "awaitingInstall")) record.status else "downloaded"
            }
            "failed" -> throw UpdateException("DOWNLOAD_STATE_FAILED", "系统下载失败，请检查网络和存储空间后重试。")
            else -> throw UpdateException("DOWNLOAD_STATE_FAILED", "系统下载状态异常，请重新下载。")
        }
        return record.copy(status = status, downloadedBytes = received.coerceAtLeast(0), totalBytes = manifest.sizeBytes,
            reason = if (status == "paused") "系统已暂停下载，将在条件允许时继续。" else null)
    }

    fun verifyStream(stream: InputStream, expectedSize: Long, expectedHash: String) {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(128 * 1024)
        var total = 0L
        while (true) {
            val read = stream.read(buffer)
            if (read < 0) break
            if (read == 0) continue
            total += read
            if (total > expectedSize) throw UpdateException("VERIFY_FAILED", "更新文件大小不正确，请重新下载。")
            digest.update(buffer, 0, read)
        }
        if (total != expectedSize || !MessageDigest.isEqual(digest.digest(), hexBytes(expectedHash))) {
            throw UpdateException("VERIFY_FAILED", "更新文件完整性校验失败，请重新下载。")
        }
    }

    fun verifyNativeLibraries(file: File, expectedAbi: String) {
        if (expectedAbi != "arm64-v8a") throw UpdateException("ABI_UNSUPPORTED", "更新安装包架构不匹配。")
        var found = false
        ZipFile(file).use { zip ->
            val entries = zip.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                if (entry.isDirectory || !entry.name.startsWith("lib/") || !entry.name.endsWith(".so")) continue
                if (!Regex("lib/arm64-v8a/[^/]+\\.so").matches(entry.name)) throw UpdateException("ABI_UNSUPPORTED", "更新安装包包含不匹配的原生架构。")
                val header = ByteArray(20)
                var offset = 0
                zip.getInputStream(entry).use { input ->
                    while (offset < header.size) {
                        val read = input.read(header, offset, header.size - offset)
                        if (read < 0) break
                        offset += read
                    }
                }
                if (offset != 20 || header[0] != 0x7f.toByte() || header[1] != 'E'.code.toByte() || header[2] != 'L'.code.toByte() ||
                    header[3] != 'F'.code.toByte() || header[4] != 2.toByte() || header[5] != 1.toByte() ||
                    header[18].toInt().and(0xff) != 183 || header[19] != 0.toByte()) {
                    throw UpdateException("ABI_UNSUPPORTED", "更新安装包的原生库不是有效的 arm64 文件。")
                }
                found = true
            }
        }
        if (!found) throw UpdateException("ABI_UNSUPPORTED", "更新安装包缺少 arm64 原生库。")
    }

    fun sameSigners(installed: Set<String>, archive: Set<String>): Boolean = installed.isNotEmpty() && installed == archive
    fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun hexBytes(hex: String): ByteArray = hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    private fun integer(value: Any?): Long = when (value) { is Int -> value.toLong(); is Long -> value; else -> invalid() }
    private fun string(value: Any?): String = (value as? String)?.takeUnless { it.isBlank() } ?: invalid()
    private fun invalid(): Nothing = throw UpdateException("INVALID_MANIFEST", "官方更新清单无效，请稍后重试或前往官方发布页。")
}
