package com.naihuishi.nai_huishi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class AppUpdateRulesTest {
    private fun manifest(): MutableMap<String, Any> = mutableMapOf(
        "schemaVersion" to 1,
        "channel" to "stable",
        "packageName" to AppUpdateRules.PACKAGE_NAME,
        "versionName" to "1.2.4",
        "versionCode" to 220053,
        "publishedAt" to "2026-10-31T08:15:00.123Z",
        "releaseNotes" to "修复与更新",
        "releaseUrl" to "${AppUpdateRules.RELEASES_URL}/tag/v1.2.4-220053",
        "apk" to mutableMapOf("url" to "${AppUpdateRules.RELEASES_URL}/download/v1.2.4-220053/app-release.apk",
            "sizeBytes" to 123456L, "sha256" to "a".repeat(64), "abi" to "arm64-v8a", "minSdk" to 24),
    )

    private fun rejects(code: String = "INVALID_MANIFEST", block: () -> Unit) {
        try {
            block()
            throw AssertionError("Expected rejection: $code")
        } catch (error: UpdateException) {
            assertEquals(code, error.code)
            assertFalse(error.message.contains("https://"))
        }
    }

    @Test fun parsesAndRoundTripsOfficialRelease() {
        val parsed = AppUpdateRules.parseManifest(manifest())
        assertEquals(220053L, parsed.versionCode)
        assertEquals(parsed, AppUpdateRules.parseManifest(parsed.toMap()))
        assertEquals("", AppUpdateRules.requireReleaseUrl(AppUpdateRules.RELEASES_URL, allowIndex = true))
        assertEquals("", AppUpdateRules.requireReleaseUrl("${AppUpdateRules.RELEASES_URL}/latest", allowIndex = true))
    }

    @Test fun rejectsUrlAuthorityAndPathBypasses() {
        val original = manifest()["releaseUrl"] as String
        val badUrls = listOf(
            original.replace("https://", "http://"),
            original.replace("github.com", "github.com.evil.invalid"),
            original.replace("github.com", "evil.invalid@github.com"),
            original.replace("github.com", "github.com@evil.invalid"),
            original.replace("github.com", "github.com:443"),
            original.replace("github.com", "GITHUB.COM"),
            original + "?download=1",
            original + "?",
            original + "#fragment",
            original + "#",
            original + "/",
            original.replace("sakiko0901", "another-owner"),
            original.replace("NAI-WorldPainter", "another-repo"),
            original.replace("v1.2.4-220053", "../v1.2.4-220053"),
            original.replace("v1.2.4-220053", "%761.2.4-220053"),
            original.replace("v1.2.4-220053", "v1.2.4%2F220053"),
            original.replace("v1.2.4-220053", "v1.2.4\\220053"),
        )
        for (url in badUrls) rejects { AppUpdateRules.parseManifest(manifest().apply { put("releaseUrl", url) }) }
    }

    @Test fun rejectsMismatchedTagAndUntrustedApk() {
        val template = manifest()
        @Suppress("UNCHECKED_CAST")
        val apk = template["apk"] as Map<String, Any>
        val original = apk["url"] as String
        for (url in listOf(original.replace("220053", "220054"), original.replace("app-release.apk", "other.apk"),
            original.replace("github.com", "evil.invalid"), "$original?secret=private", "$original#fragment",
            original.replace("github.com", "github.com:443"), original.replace("github.com", "user@github.com"))) {
            rejects { AppUpdateRules.parseManifest(manifest().apply { put("apk", apk + ("url" to url)) }) }
        }
    }

    @Test fun rejectsPreviewAndMalformedManifests() {
        for ((key, value) in listOf("schemaVersion" to 2, "schemaVersion" to 1.0, "channel" to "preview",
            "packageName" to "${AppUpdateRules.PACKAGE_NAME}.preview", "versionCode" to 0,
            "versionCode" to 220053.0, "versionCode" to (Int.MAX_VALUE.toLong() + 1), "unknownField" to true,
            "versionName" to "1.2.4-preview.1", "versionName" to "1.2.4-rc1",
            "publishedAt" to "2026-02-30T08:15:00Z", "publishedAt" to "2026-10-31",
            "publishedAt" to "2026-10-31T25:15:00Z", "publishedAt" to "1969-01-01T08:15:00Z",
            "publishedAt" to "2026-10-31T08:15:00+14:01", "publishedAt" to "2026-10-31T08:15:00.123456789Z",
            "releaseNotes" to "x".repeat(64 * 1024 + 1), "releaseNotes" to "\u0000unsafe")) {
            rejects { AppUpdateRules.parseManifest(manifest().apply { put(key, value) }) }
        }
        for (tag in listOf("v1.2.4-preview.1", "v1.2.4-rc1", "test-v1.2.4", "v1.2.4-beta", "v1.2.4-dev")) {
            rejects { AppUpdateRules.requireReleaseUrl("${AppUpdateRules.RELEASES_URL}/tag/$tag") }
        }
        @Suppress("UNCHECKED_CAST")
        val apk = manifest()["apk"] as Map<String, Any>
        for ((key, value) in listOf("sizeBytes" to 0, "sizeBytes" to -1, "sizeBytes" to (512L * 1024 * 1024 + 1),
            "minSdk" to 20, "minSdk" to 101, "unknownField" to true,
            "sha256" to "g".repeat(64), "sha256" to "a".repeat(63), "abi" to "x86_64")) {
            rejects { AppUpdateRules.parseManifest(manifest().apply { put("apk", apk + (key to value)) }) }
        }
    }

    @Test fun checksInstalledPackageUpgradeSdkAndAbi() {
        val parsed = AppUpdateRules.parseManifest(manifest())
        AppUpdateRules.requireEligible(parsed, AppUpdateRules.PACKAGE_NAME, 220052, 24, listOf("arm64-v8a", "armeabi-v7a"))
        rejects("PACKAGE_MISMATCH") { AppUpdateRules.requireEligible(parsed, "${AppUpdateRules.PACKAGE_NAME}.preview", 1, 36, listOf("arm64-v8a")) }
        rejects("NOT_NEWER") { AppUpdateRules.requireEligible(parsed, AppUpdateRules.PACKAGE_NAME, 220053, 36, listOf("arm64-v8a")) }
        rejects("NOT_NEWER") { AppUpdateRules.requireEligible(parsed, AppUpdateRules.PACKAGE_NAME, 220054, 36, listOf("arm64-v8a")) }
        rejects("SDK_UNSUPPORTED") { AppUpdateRules.requireEligible(parsed, AppUpdateRules.PACKAGE_NAME, 1, 23, listOf("arm64-v8a")) }
        rejects("ABI_UNSUPPORTED") { AppUpdateRules.requireEligible(parsed, AppUpdateRules.PACKAGE_NAME, 1, 36, listOf("x86_64")) }
    }

    @Test fun verifiesStreamingSizeAndDigest() {
        val bytes = ByteArray(320_007) { (it % 251).toByte() }
        val hash = AppUpdateRules.sha256(bytes)
        AppUpdateRules.verifyStream(ByteArrayInputStream(bytes), bytes.size.toLong(), hash)
        rejects("VERIFY_FAILED") { AppUpdateRules.verifyStream(ByteArrayInputStream(bytes), bytes.size.toLong() - 1, hash) }
        rejects("VERIFY_FAILED") { AppUpdateRules.verifyStream(ByteArrayInputStream(bytes), bytes.size.toLong() + 1, hash) }
        rejects("VERIFY_FAILED") { AppUpdateRules.verifyStream(ByteArrayInputStream(bytes.apply { this[200_000] = 1 }), bytes.size.toLong(), hash) }
    }

    @Test fun requiresExactNonemptySignerSet() {
        val one = "a".repeat(64)
        val two = "b".repeat(64)
        assertTrue(AppUpdateRules.sameSigners(setOf(one), setOf(one)))
        assertTrue(AppUpdateRules.sameSigners(setOf(one, two), setOf(two, one)))
        assertFalse(AppUpdateRules.sameSigners(emptySet(), emptySet()))
        assertFalse(AppUpdateRules.sameSigners(setOf(one), setOf(two)))
        assertFalse(AppUpdateRules.sameSigners(setOf(one, two), setOf(one)))
    }

    @Test fun downloadCompletionRequiresSeparateVerificationBeforeReady() {
        val parsed = AppUpdateRules.parseManifest(manifest())
        val downloading = UpdateRecord(parsed, 42, "running")
        val complete = AppUpdateRules.reconcileDownload(downloading, "successful", parsed.sizeBytes, parsed.sizeBytes, parsed.sizeBytes)
        assertEquals("downloaded", complete.status)
        for (verifiedStatus in listOf("ready", "awaitingInstall")) {
            assertEquals(verifiedStatus, AppUpdateRules.reconcileDownload(complete.copy(status = verifiedStatus), "successful",
                parsed.sizeBytes, parsed.sizeBytes, parsed.sizeBytes).status)
        }
        val paused = AppUpdateRules.reconcileDownload(downloading, "paused", -1, -1, null)
        assertEquals(0L, paused.downloadedBytes)
        assertEquals(parsed.sizeBytes, paused.totalBytes)
        assertTrue(paused.reason != null)
    }

    @Test fun missingTaskOrFileNeverRestoresReadyOrAwaitingInstall() {
        val parsed = AppUpdateRules.parseManifest(manifest())
        for (status in listOf("downloaded", "ready", "awaitingInstall")) {
            val previous = UpdateRecord(parsed, 42, status)
            rejects("DOWNLOAD_STATE_FAILED") { AppUpdateRules.reconcileDownload(previous, null, 0, -1, parsed.sizeBytes) }
            rejects("DOWNLOAD_STATE_FAILED") { AppUpdateRules.reconcileDownload(previous, "successful", parsed.sizeBytes, parsed.sizeBytes, null) }
            rejects("DOWNLOAD_STATE_FAILED") { AppUpdateRules.reconcileDownload(previous, "successful", parsed.sizeBytes, parsed.sizeBytes, parsed.sizeBytes - 1) }
            rejects("DOWNLOAD_STATE_FAILED") { AppUpdateRules.reconcileDownload(previous, "running", 1, parsed.sizeBytes, null) }
            rejects("DOWNLOAD_STATE_FAILED") { AppUpdateRules.reconcileDownload(previous, "failed", 1, parsed.sizeBytes, null) }
        }
        val downloading = UpdateRecord(parsed, 42, "running")
        rejects("DOWNLOAD_STATE_FAILED") { AppUpdateRules.reconcileDownload(downloading, "running", parsed.sizeBytes + 1, -1, null) }
        rejects("DOWNLOAD_STATE_FAILED") { AppUpdateRules.reconcileDownload(downloading, "running", 1, parsed.sizeBytes - 1, null) }
    }

    @Test fun checksNativeZipDirectoriesAndActualElfMachine() {
        val arm64 = ByteArray(20).apply {
            this[0] = 0x7f
            this[1] = 'E'.code.toByte(); this[2] = 'L'.code.toByte(); this[3] = 'F'.code.toByte()
            this[4] = 2; this[5] = 1; this[18] = 183.toByte()
        }
        withZip(mapOf("lib/arm64-v8a/libflutter.so" to arm64)) { AppUpdateRules.verifyNativeLibraries(it, "arm64-v8a") }
        for (entries in listOf(
            mapOf("assets/data" to arm64),
            mapOf("lib/x86_64/libflutter.so" to arm64),
            mapOf("lib/arm64-v8a/libflutter.so" to arm64, "lib/armeabi-v7a/libother.so" to arm64),
            mapOf("lib/arm64-v8a/libflutter.so" to arm64.copyOf().apply { this[18] = 62 }),
            mapOf("lib/arm64-v8a/libflutter.so" to arm64.copyOf().apply { this[4] = 1 }),
            mapOf("lib/arm64-v8a/libflutter.so" to byteArrayOf(1, 2, 3)),
        )) withZip(entries) { file -> rejects("ABI_UNSUPPORTED") { AppUpdateRules.verifyNativeLibraries(file, "arm64-v8a") } }
    }

    private fun withZip(entries: Map<String, ByteArray>, block: (File) -> Unit) {
        val file = File.createTempFile("app-update-rules-", ".apk")
        try {
            ZipOutputStream(file.outputStream()).use { output ->
                for ((name, bytes) in entries) {
                    output.putNextEntry(ZipEntry(name)); output.write(bytes); output.closeEntry()
                }
            }
            block(file)
        } finally { file.delete() }
    }
}
