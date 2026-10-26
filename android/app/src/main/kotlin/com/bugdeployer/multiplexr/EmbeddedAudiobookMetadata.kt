package com.bugdeployer.multiplexr

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Bounded ISO BMFF reader. Skips audio payloads, including multi-gigabyte M4Bs. */
object EmbeddedAudiobookMetadata {
    data class Chapter(val startMs: Long, val title: String)
    data class Result(val chapters: List<Chapter>, val series: String = "", val order: Double = 0.0)
    private data class Atom(val type: String, val start: Int, val end: Int)
    private fun int(bytes: ByteArray, at: Int): Int = ByteBuffer.wrap(bytes, at, 4).order(ByteOrder.BIG_ENDIAN).int
    private fun long(bytes: ByteArray, at: Int): Long = ByteBuffer.wrap(bytes, at, 8).order(ByteOrder.BIG_ENDIAN).long
    private fun uint(bytes: ByteArray, at: Int): Long = int(bytes, at).toLong() and 0xffffffffL
    private fun atoms(bytes: ByteArray, from: Int, to: Int): List<Atom> {
        val values = mutableListOf<Atom>(); var at = from
        while (at + 8 <= to) {
            var size = uint(bytes, at); var header = 8
            if (size == 1L) { require(at + 16 <= to); size = long(bytes, at + 8); header = 16 }
            if (size == 0L) size = (to - at).toLong()
            require(size >= header && size <= to - at) { "Invalid chapter metadata atom." }
            values.add(Atom(String(bytes, at + 4, 4, Charsets.ISO_8859_1), at + header, at + size.toInt()))
            require(values.size <= 100000)
            at += size.toInt()
        }
        return values
    }
    fun read(size: Long, read: (Long, Int) -> ByteArray): Result {
        if (size >= 10 && String(read(0, 3), Charsets.ISO_8859_1) == "ID3") return id3(size, read)
        if (size < 8 || String(read(4, 4), Charsets.ISO_8859_1) !in setOf("ftyp", "moov", "mdat", "free", "wide", "skip")) return Result(emptyList())
        var offset = 0L; var count = 0
        while (offset <= size - 8 && count++ < 100000) {
            val header = read(offset, 8)
            var length = uint(header, 0); var headerSize = 8
            if (length == 1L) { require(offset <= size - 16); length = long(read(offset + 8, 8), 0); headerSize = 16 }
            if (length == 0L) length = size - offset
            require(length >= headerSize && length <= size - offset)
            if (String(header, 4, 4, Charsets.ISO_8859_1) == "moov") {
                require(length <= 32_000_000) { "Book metadata exceeds supported size." }
                return parse(read(offset + headerSize, (length - headerSize).toInt()), read)
            }
            offset += length
        }
        return Result(emptyList())
    }
    private fun id3(size: Long, read: (Long, Int) -> ByteArray): Result {
        val header = read(0, 10); val version = header[3].toInt()
        require(version in 3..4 && header[5].toInt() and 0xc0 == 0) { "Unsupported ID3 chapter encoding." }
        fun sync(bytes: ByteArray, at: Int): Int {
            var value = 0
            repeat(4) { val n = bytes[at + it].toInt() and 255; require(n < 128); value = (value shl 7) or n }
            return value
        }
        val length = sync(header, 6); require(length <= 2_000_000 && length <= size - 10)
        val bytes = read(10, length)
        fun text(data: ByteArray): String {
            if (data.isEmpty()) return ""
            val encoding = when (data[0].toInt()) { 0 -> Charsets.ISO_8859_1; 1 -> Charsets.UTF_16; 2 -> Charsets.UTF_16BE; 3 -> Charsets.UTF_8; else -> throw IllegalArgumentException("Invalid ID3 text encoding.") }
            return String(data, 1, data.size - 1, encoding).trim('\u0000', ' ')
        }
        fun frames(from: Int, to: Int): List<Pair<String, ByteArray>> {
            val output = mutableListOf<Pair<String, ByteArray>>(); var at = from
            while (at + 10 <= to && bytes[at].toInt() != 0) {
                val name = String(bytes, at, 4, Charsets.ISO_8859_1)
                val n = if (version == 4) sync(bytes, at + 4) else int(bytes, at + 4)
                require(n >= 0 && n <= to - at - 10 && output.size < 10000)
                if (bytes[at + 9].toInt() == 0) output.add(name to bytes.copyOfRange(at + 10, at + 10 + n))
                at += 10 + n
            }
            return output
        }
        var series = ""; var order = 0.0; val chapters = mutableListOf<Chapter>()
        for ((name, data) in frames(0, bytes.size)) {
            if (name == "TXXX") {
                val decoded = text(data); val key = decoded.substringBefore('\u0000').lowercase(); val value = decoded.substringAfter('\u0000', "").trim('\u0000', ' ')
                if (key in setOf("series", "seriesname", "series_name")) series = value
                if (key in setOf("series-part", "series_index", "seriesindex")) order = value.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 } ?: 0.0
            }
            if (name == "CHAP") {
                val nullAt = data.indexOf(0); require(nullAt >= 0 && nullAt + 17 <= data.size && chapters.size < 1000)
                val start = uint(data, nullAt + 1)
                var title = "Chapter ${chapters.size + 1}"; var at = nullAt + 17
                while (at + 10 <= data.size) {
                    val n = if (version == 4) sync(data, at + 4) else int(data, at + 4)
                    require(n >= 0 && n <= data.size - at - 10)
                    if (String(data, at, 4, Charsets.ISO_8859_1) == "TIT2") title = text(data.copyOfRange(at + 10, at + 10 + n)).ifBlank { title }
                    at += 10 + n
                }
                chapters.add(Chapter(start, title))
            }
        }
        return Result(chapters.sortedBy { it.startMs }.distinctBy { it.startMs }, series, order)
    }
    private fun parse(bytes: ByteArray, read: (Long, Int) -> ByteArray): Result {
        var chapters = emptyList<Chapter>(); var series = ""; var order = 0.0
        fun visit(from: Int, to: Int, depth: Int) {
            require(depth <= 12)
            for (atom in atoms(bytes, from, to)) when (atom.type) {
                "udta", "ilst" -> visit(atom.start, atom.end, depth + 1)
                "meta" -> if (atom.end - atom.start >= 4) visit(atom.start + 4, atom.end, depth + 1)
                "chpl" -> {
                    var at = atom.start
                    require(atom.end - at >= 5)
                    val version = bytes[at].toInt() and 255
                    at += 4
                    if (version != 0) at += 4
                    require(at < atom.end)
                    val n = bytes[at++].toInt() and 255
                    val values = mutableListOf<Chapter>()
                    repeat(n) {
                        require(at + 9 <= atom.end)
                        val time = long(bytes, at); at += 8
                        val length = bytes[at++].toInt() and 255
                        require(time >= 0 && at + length <= atom.end)
                        val title = String(bytes, at, length, Charsets.UTF_8).trim(); at += length
                        values.add(Chapter(time / 10000, title.ifBlank { "Chapter ${it + 1}" }))
                    }
                    chapters = values
                }
                "----" -> {
                    val fields = atoms(bytes, atom.start, atom.end)
                    fun value(type: String, skip: Int) = fields.firstOrNull { it.type == type }?.let { if (it.end - it.start >= skip) String(bytes, it.start + skip, it.end - it.start - skip, Charsets.UTF_8).trim('\u0000', ' ') else "" } ?: ""
                    val name = value("name", 4).lowercase(); val data = value("data", 8)
                    if (name in setOf("series", "seriesname", "series_name")) series = data
                    if (name in setOf("series-part", "series_index", "seriesindex", "series-part-number")) order = data.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 } ?: 0.0
                }
            }
        }
        visit(0, bytes.size, 0)
        if (chapters.isEmpty()) chapters = quickTimeChapters(bytes, read)
        require(chapters.size <= 1000)
        return Result(chapters.sortedBy { it.startMs }.distinctBy { it.startMs }, series, order)
    }
    private fun quickTimeChapters(bytes: ByteArray, read: (Long, Int) -> ByteArray): List<Chapter> {
        val tracks = atoms(bytes, 0, bytes.size).filter { it.type == "trak" }
        fun children(a: Atom) = atoms(bytes, a.start, a.end)
        val ids = tracks.flatMap { track -> children(track).filter { it.type == "tref" }.flatMap { children(it) }.filter { it.type == "chap" }.flatMap { a -> (a.start until a.end step 4).map { int(bytes, it) } } }.toSet()
        for (track in tracks) {
            val tkhd = children(track).firstOrNull { it.type == "tkhd" } ?: continue
            val idOffset = if (bytes[tkhd.start].toInt() == 1) 20 else 12
            if (tkhd.start + idOffset + 4 > tkhd.end || int(bytes, tkhd.start + idOffset) !in ids) continue
            val mdia = children(track).firstOrNull { it.type == "mdia" } ?: continue
            val mdhd = children(mdia).firstOrNull { it.type == "mdhd" } ?: continue
            val timeOffset = if (bytes[mdhd.start].toInt() == 1) 20 else 12
            require(mdhd.start + timeOffset + 4 <= mdhd.end)
            val scale = uint(bytes, mdhd.start + timeOffset); require(scale > 0)
            val minf = children(mdia).firstOrNull { it.type == "minf" } ?: continue
            val stbl = children(minf).firstOrNull { it.type == "stbl" } ?: continue
            val tables = children(stbl).associateBy { it.type }
            val sizes = tables["stsz"] ?: continue
            require(sizes.end - sizes.start >= 12)
            val n = int(bytes, sizes.start + 8); require(n in 1..1000)
            val uniform = int(bytes, sizes.start + 4)
            val lengths = (0 until n).map { i -> if (uniform != 0) uniform else { require(sizes.start + 16 + i * 4 <= sizes.end); int(bytes, sizes.start + 12 + i * 4) } }
            require(lengths.all { it in 2..65536 })
            val timing = tables["stts"] ?: continue
            val times = mutableListOf<Long>(); var ticks = 0L
            require(timing.end - timing.start >= 8)
            val entries = int(bytes, timing.start + 4); require(entries in 1..1000)
            repeat(entries) { i ->
                val at = timing.start + 8 + i * 8; require(at + 8 <= timing.end)
                val samples = int(bytes, at); val delta = uint(bytes, at + 4); require(samples in 0..n && times.size + samples <= n)
                repeat(samples) { times.add(ticks * 1000 / scale); ticks += delta }
            }
            require(times.size == n)
            val offsets = tables["stco"] ?: tables["co64"] ?: continue
            val step = if (offsets.type == "co64") 8 else 4
            require(offsets.end - offsets.start >= 8)
            val chunks = int(bytes, offsets.start + 4); require(chunks in 1..1000)
            val chunkOffsets = (0 until chunks).map { i -> val at = offsets.start + 8 + i * step; require(at + step <= offsets.end); if (step == 8) long(bytes, at) else uint(bytes, at) }
            val mapping = tables["stsc"] ?: continue
            require(mapping.end - mapping.start >= 8)
            val mappings = int(bytes, mapping.start + 4); require(mappings in 1..1000)
            val ranges = (0 until mappings).map { i -> val at = mapping.start + 8 + i * 12; require(at + 12 <= mapping.end); int(bytes, at) to int(bytes, at + 4) }
            require(ranges.first().first == 1 && ranges.all { it.second in 1..1000 } && ranges.zipWithNext().all { it.first.first < it.second.first })
            val output = mutableListOf<Chapter>(); var sample = 0
            for ((index, start) in chunkOffsets.withIndex()) {
                var offset = start
                val perChunk = ranges.last { it.first <= index + 1 }.second
                repeat(perChunk) {
                    require(sample < n && offset >= 0)
                    val data = read(offset, lengths[sample]); offset += data.size
                    val titleLength = ((data[0].toInt() and 255) shl 8) or (data[1].toInt() and 255)
                    require(titleLength <= data.size - 2)
                    val title = String(data, 2, titleLength, Charsets.UTF_8).trim()
                    output.add(Chapter(times[sample], title.ifBlank { "Chapter ${sample + 1}" })); sample++
                }
            }
            require(sample == n)
            return output
        }
        return emptyList()
    }
}
