package com.bugdeployer.multiplexr.plugins

import android.os.Build
import android.system.Os
import java.io.File

/** Android 24/25 lack java.nio.file. Both implementations replace atomically in
 * the same directory; never delete the live file before replacement. */
internal object PluginAtomicReplace {
    fun move(source: File, target: File) {
        if (Build.VERSION.SDK_INT in 1..25) Os.rename(source.absolutePath, target.absolutePath)
        else NioReplace.move(source, target) // SDK_INT=0 is the host JVM test stub.
    }
    // Keep API-26 types in a separate class, unloaded on older Android.
    private object NioReplace {
        fun move(source: File, target: File) {
            java.nio.file.Files.move(source.toPath(), target.toPath(),
                java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                java.nio.file.StandardCopyOption.ATOMIC_MOVE)
        }
    }
}
