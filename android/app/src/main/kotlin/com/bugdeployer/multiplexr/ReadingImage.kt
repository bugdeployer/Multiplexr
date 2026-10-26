package com.bugdeployer.multiplexr

/** Header bounds only; the renderer still validates/decodes pixels lazily. */
object ReadingImage {
    fun validate(bytes: ByteArray) { dimensions(bytes) }
    fun dimensions(bytes: ByteArray): Pair<Int, Int> {
        fun u(i: Int) = bytes[i].toInt() and 255
        fun le(i: Int) = u(i) or (u(i + 1) shl 8) or (u(i + 2) shl 16)
        fun be(i: Int) = (u(i).toLong() shl 24) or (u(i + 1).toLong() shl 16) or (u(i + 2).toLong() shl 8) or u(i + 3).toLong()
        require(bytes.size >= 24) { "Invalid image header." }
        val dimensions: Pair<Long, Long> = when {
            bytes.copyOfRange(0, 8).contentEquals(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)) -> be(16) to be(20)
            String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF" && String(bytes, 8, 4, Charsets.US_ASCII) == "WEBP" -> {
                when (String(bytes, 12, 4, Charsets.US_ASCII)) {
                    "VP8X" -> { require(bytes.size >= 30); (le(24) + 1).toLong() to (le(27) + 1).toLong() }
                    "VP8L" -> { require(bytes.size >= 25 && u(20) == 47); ((u(21) or ((u(22) and 63) shl 8)) + 1).toLong() to (((u(22) shr 6) or (u(23) shl 2) or ((u(24) and 15) shl 10)) + 1).toLong() }
                    "VP8 " -> { require(bytes.size >= 30 && u(23) == 157 && u(24) == 1 && u(25) == 42); ((u(26) or (u(27) shl 8)) and 16383).toLong() to ((u(28) or (u(29) shl 8)) and 16383).toLong() }
                    else -> error("Unsupported WebP header.")
                }
            }
            u(0) == 255 && u(1) == 216 -> {
                var i = 2; var found: Pair<Long, Long>? = null
                while (i + 8 < bytes.size) {
                    require(u(i) == 255); while (i < bytes.size && u(i) == 255) i++
                    require(i < bytes.size); val marker = u(i++)
                    if (marker == 217 || marker == 218) break
                    if (marker in 208..215 || marker == 1) continue
                    require(i + 1 < bytes.size); val length = (u(i) shl 8) or u(i + 1); require(length >= 2 && i + length <= bytes.size)
                    if (marker in setOf(192, 193, 194, 195, 197, 198, 199, 201, 202, 203, 205, 206, 207)) {
                        require(length >= 8); found = ((u(i + 5) shl 8) or u(i + 6)).toLong() to ((u(i + 3) shl 8) or u(i + 4)).toLong(); break
                    }
                    i += length
                }
                found ?: error("JPEG dimensions not found within header limit.")
            }
            else -> error("Unsupported image header.")
        }
        require(dimensions.first in 1..40000 && dimensions.second in 1..40000 && dimensions.first * dimensions.second <= 100000000) { "Image dimensions exceed decode limits." }
        return dimensions.first.toInt() to dimensions.second.toInt()
    }
}
