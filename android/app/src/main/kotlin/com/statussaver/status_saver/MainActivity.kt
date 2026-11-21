package com.statussaver.status_saver

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val channelName = "status_saver/saf"
    private val reqTree = 4201
    private val reqLegacy = 4202
    private val saveFolder = "StatusSaver"

    private val io = Executors.newFixedThreadPool(3)
    private val main = Handler(Looper.getMainLooper())
    private var pendingResult: MethodChannel.Result? = null

    private val imageExt = setOf("jpg", "jpeg", "png", "webp", "gif")
    private val videoExt = setOf("mp4", "3gp", "mkv", "webm")

    private val useSaf get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val pkg = call.argument<String>("pkg") ?: "com.whatsapp"
        when (call.method) {
            "isInstalled" -> result.success(isInstalled(pkg))
            "hasPermission" -> result.success(hasPermission(pkg))
            "requestPermission" -> requestPermission(pkg, result)
            "listStatuses" -> background(result) { listStatuses(pkg) }
            "listSaved" -> background(result) { listSaved() }
            "cacheFile" -> background(result) {
                cacheFile(Uri.parse(call.argument<String>("uri")!!), call.argument<String>("name")!!)
            }
            "videoThumbnail" -> background(result) {
                videoThumbnail(Uri.parse(call.argument<String>("uri")!!), call.argument<String>("name")!!)
            }
            "save" -> background(result) {
                save(
                    Uri.parse(call.argument<String>("uri")!!),
                    call.argument<String>("name")!!,
                    call.argument<Boolean>("isVideo") ?: false,
                )
            }
            "delete" -> background(result) { delete(Uri.parse(call.argument<String>("uri")!!)) }
            "share" -> {
                try {
                    share(
                        call.argument<String>("path")!!,
                        call.argument<Boolean>("isVideo") ?: false,
                        call.argument<String>("target"),
                    )
                    result.success(true)
                } catch (e: Exception) {
                    android.util.Log.e("StatusSaver", "share failed", e)
                    result.error("share_failed", "${e.javaClass.simpleName}: ${e.message}", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("error", e.message, null) }
            }
        }
    }

    // ---------------------------------------------------------------- permission

    private fun isInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0); true
    } catch (e: Exception) {
        false
    }

    private fun statusesDocId(pkg: String) = "primary:Android/media/$pkg/WhatsApp/Media/.Statuses"

    private fun persistedTree(pkg: String): Uri? {
        val docId = statusesDocId(pkg)
        return contentResolver.persistedUriPermissions
            .firstOrNull {
                it.isReadPermission &&
                    runCatching { DocumentsContract.getTreeDocumentId(it.uri) }.getOrNull() == docId
            }?.uri
    }

    private fun hasPermission(pkg: String): Boolean =
        if (useSaf) persistedTree(pkg) != null
        else checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(pkg: String, result: MethodChannel.Result) {
        if (hasPermission(pkg)) {
            result.success(true); return
        }
        pendingResult?.success(false)
        pendingResult = result
        if (useSaf) {
            val initial = DocumentsContract.buildDocumentUri(
                "com.android.externalstorage.documents", statusesDocId(pkg)
            )
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, initial)
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                )
            }
            intent.putExtra("pkg", pkg)
            requestedPkg = pkg
            startActivityForResult(intent, reqTree)
        } else {
            requestPermissions(
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ),
                reqLegacy,
            )
        }
    }

    private var requestedPkg: String = "com.whatsapp"

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqTree) return
        val uri = data?.data
        var ok = false
        if (resultCode == RESULT_OK && uri != null) {
            val picked = runCatching { DocumentsContract.getTreeDocumentId(uri) }.getOrNull()
            if (picked == statusesDocId(requestedPkg)) {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                ok = true
            }
        }
        pendingResult?.success(ok)
        pendingResult = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != reqLegacy) return
        val ok = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingResult?.success(ok)
        pendingResult = null
    }

    // ---------------------------------------------------------------- listing

    private fun kindOf(name: String): String? {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            in imageExt -> "image"
            in videoExt -> "video"
            else -> null
        }
    }

    private fun entry(uri: String, name: String, kind: String, modified: Long) = mapOf(
        "uri" to uri,
        "name" to name,
        "isVideo" to (kind == "video"),
        "lastModified" to modified,
    )

    private fun listStatuses(pkg: String): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        if (useSaf) {
            val tree = persistedTree(pkg) ?: return out
            val dir = DocumentFile.fromTreeUri(this, tree) ?: return out
            for (f in dir.listFiles()) {
                val name = f.name ?: continue
                if (!f.isFile || name.startsWith(".")) continue
                val kind = kindOf(name) ?: continue
                out.add(entry(f.uri.toString(), name, kind, f.lastModified()))
            }
        } else {
            val root = Environment.getExternalStorageDirectory()
            val base = if (pkg == "com.whatsapp.w4b") "WhatsApp Business" else "WhatsApp"
            val dirs = listOf(
                File(root, "$base/Media/.Statuses"),
                File(root, "Android/media/$pkg/WhatsApp/Media/.Statuses"),
            )
            val seen = HashSet<String>()
            for (d in dirs) {
                d.listFiles()?.forEach { f ->
                    if (!f.isFile || f.name.startsWith(".") || !seen.add(f.name)) return@forEach
                    val kind = kindOf(f.name) ?: return@forEach
                    out.add(entry(Uri.fromFile(f).toString(), f.name, kind, f.lastModified()))
                }
            }
        }
        out.sortByDescending { it["lastModified"] as Long }
        return out
    }

    private fun listSaved(): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            querySaved(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "image", Environment.DIRECTORY_PICTURES, out)
            querySaved(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, "video", Environment.DIRECTORY_MOVIES, out)
        } else {
            for (type in listOf(Environment.DIRECTORY_PICTURES, Environment.DIRECTORY_MOVIES)) {
                val dir = File(Environment.getExternalStoragePublicDirectory(type), saveFolder)
                dir.listFiles()?.forEach { f ->
                    val kind = kindOf(f.name) ?: return@forEach
                    out.add(entry(Uri.fromFile(f).toString(), f.name, kind, f.lastModified()))
                }
            }
        }
        out.sortByDescending { it["lastModified"] as Long }
        return out
    }

    private fun querySaved(collection: Uri, kind: String, dirType: String, out: MutableList<Map<String, Any>>) {
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.DATE_MODIFIED,
        )
        contentResolver.query(
            collection, projection,
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
            arrayOf("$dirType/$saveFolder%"),
            null,
        )?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameCol = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val modCol = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            while (c.moveToNext()) {
                val uri = Uri.withAppendedPath(collection, c.getLong(idCol).toString())
                out.add(entry(uri.toString(), c.getString(nameCol), kind, c.getLong(modCol) * 1000))
            }
        }
    }

    // ---------------------------------------------------------------- files

    private fun cacheDirFor(sub: String) = File(cacheDir, sub).apply { mkdirs() }

    private fun cacheFile(uri: Uri, name: String): String {
        if (uri.scheme == "file") return uri.path!!
        val target = File(cacheDirFor("statuses"), name)
        if (target.exists() && target.length() > 0) return target.absolutePath
        contentResolver.openInputStream(uri)!!.use { input ->
            FileOutputStream(target).use { input.copyTo(it) }
        }
        return target.absolutePath
    }

    private fun videoThumbnail(uri: Uri, name: String): String? {
        val target = File(cacheDirFor("thumbs"), "$name.jpg")
        if (target.exists() && target.length() > 0) return target.absolutePath
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(this, uri)
            val frame = retriever.getFrameAtTime(0) ?: return null
            val scale = 360f / maxOf(frame.width, frame.height)
            val bmp = if (scale < 1f) Bitmap.createScaledBitmap(
                frame, (frame.width * scale).toInt(), (frame.height * scale).toInt(), true
            ) else frame
            FileOutputStream(target).use { bmp.compress(Bitmap.CompressFormat.JPEG, 80, it) }
            return target.absolutePath
        } finally {
            retriever.release()
        }
    }

    private fun mimeOf(name: String, isVideo: Boolean): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when {
            isVideo && ext == "3gp" -> "video/3gpp"
            isVideo -> "video/mp4"
            ext == "png" -> "image/png"
            ext == "webp" -> "image/webp"
            ext == "gif" -> "image/gif"
            else -> "image/jpeg"
        }
    }

    private fun save(uri: Uri, name: String, isVideo: Boolean): String {
        val mime = mimeOf(name, isVideo)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val dirType = if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$dirType/$saveFolder")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val dest = contentResolver.insert(collection, values) ?: error("Could not create file")
            try {
                contentResolver.openInputStream(uri)!!.use { input ->
                    contentResolver.openOutputStream(dest)!!.use { input.copyTo(it) }
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(dest, values, null, null)
            } catch (e: Exception) {
                contentResolver.delete(dest, null, null)
                throw e
            }
            return dest.toString()
        } else {
            val dirType = if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
            val dir = File(Environment.getExternalStoragePublicDirectory(dirType), saveFolder).apply { mkdirs() }
            val target = File(dir, name)
            contentResolver.openInputStream(uri)!!.use { input ->
                FileOutputStream(target).use { input.copyTo(it) }
            }
            MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf(mime), null)
            return Uri.fromFile(target).toString()
        }
    }

    private fun delete(uri: Uri): Boolean {
        return if (uri.scheme == "file") {
            val f = File(uri.path!!)
            val ok = f.delete()
            MediaScannerConnection.scanFile(this, arrayOf(f.absolutePath), null, null)
            ok
        } else {
            contentResolver.delete(uri, null, null) > 0
        }
    }

    private fun share(path: String, isVideo: Boolean, target: String?) {
        // Always share a copy from our own cache dir so FileProvider can serve it
        // regardless of where the original lives (WhatsApp folder, MediaStore, ...).
        val src = File(path)
        val file = File(cacheDirFor("share"), src.name)
        if (src.absolutePath != file.absolutePath) src.copyTo(file, overwrite = true)
        val uri = FileProvider.getUriForFile(this, "$packageName.statusprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeOf(file.name, isVideo)
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (target != null) setPackage(target)
        }
        if (target != null) startActivity(intent)
        else startActivity(Intent.createChooser(intent, "Share via"))
    }
}
