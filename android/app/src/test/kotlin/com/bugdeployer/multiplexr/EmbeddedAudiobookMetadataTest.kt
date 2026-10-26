package com.bugdeployer.multiplexr

import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import org.json.JSONObject

class EmbeddedAudiobookMetadataTest {
    private fun number(value: Int) = ByteBuffer.allocate(4).putInt(value).array()
    private fun long(value: Long) = ByteBuffer.allocate(8).putLong(value).array()
    private fun atom(name: String, data: ByteArray) = number(data.size + 8) + name.toByteArray() + data
    private fun read(data: ByteArray): EmbeddedAudiobookMetadata.Result = EmbeddedAudiobookMetadata.read(data.size.toLong()) { position, length -> data.copyOfRange(position.toInt(), position.toInt() + length) }
    private fun chpl(version: Int = 1): ByteArray {
        val prefix = byteArrayOf(version.toByte(), 0, 0, 0) + (if (version != 0) number(0) else byteArrayOf()) + byteArrayOf(2)
        return atom("chpl", prefix + long(0) + byteArrayOf(3) + "One".toByteArray() + long(15_000L * 10000) + byteArrayOf(3) + "Two".toByteArray())
    }
    @Test fun readsNeroChapterMarkersWithMillisecondTimes() {
        val result = read(atom("ftyp", "M4B ".toByteArray()) + atom("moov", atom("udta", chpl())))
        assertEquals(listOf(0L, 15000L), result.chapters.map { it.startMs })
        assertEquals(listOf("One", "Two"), result.chapters.map { it.title })
    }
    @Test fun readsVersionZeroChapterLists() { assertEquals(2, read(atom("moov", atom("udta", chpl(0)))).chapters.size) }
    @Test fun unchapteredBookRemainsAWholeFile() { assertTrue(read(atom("moov", byteArrayOf())).chapters.isEmpty()) }
    @Test fun rejectsTruncatedAtoms() { assertThrows(IllegalArgumentException::class.java) { read(number(100) + "moov".toByteArray()) } }
    @Test fun readsSeriesAndFractionalBookNumberFromFreeformTags() {
        fun tag(name: String, value: String) = atom("----", atom("mean", number(0) + "com.apple.iTunes".toByteArray()) + atom("name", number(0) + name.toByteArray()) + atom("data", number(1) + number(0) + value.toByteArray()))
        val result = read(atom("moov", atom("udta", atom("meta", number(0) + atom("ilst", tag("SERIES", "A trilogy") + tag("SERIES-PART", "1.5"))))))
        assertEquals("A trilogy", result.series); assertEquals(1.5, result.order, 0.0)
    }
    @Test fun skipsLargeAudioPayloadsWithoutReadingThem() {
        val moov = atom("moov", atom("udta", chpl())); val start = 5_000_000_000L
        val result = EmbeddedAudiobookMetadata.read(start + moov.size) { position, length ->
            if (position < 16) (number(1) + "mdat".toByteArray() + long(start)).copyOfRange(position.toInt(), position.toInt() + length) else moov.copyOfRange((position - start).toInt(), (position - start).toInt() + length)
        }
        assertEquals(2, result.chapters.size)
    }
    @Test fun readsQuickTimeTextChapterTrack() {
        val first = byteArrayOf(0, 3) + "One".toByteArray(); val second = byteArrayOf(0, 3) + "Two".toByteArray()
        val payload = atom("mdat", first + second)
        val audioTrack = atom("trak", atom("tref", atom("chap", number(2))))
        val tables = atom("stsz", number(0) + number(0) + number(2) + number(first.size) + number(second.size)) +
            atom("stts", number(0) + number(1) + number(2) + number(15000)) +
            atom("stco", number(0) + number(1) + number(8)) + atom("stsc", number(0) + number(1) + number(1) + number(2) + number(1))
        val chapterTrack = atom("trak", atom("tkhd", number(0) + number(0) + number(0) + number(2)) + atom("mdia", atom("mdhd", number(0) + number(0) + number(0) + number(1000)) + atom("minf", atom("stbl", tables))))
        val result = read(payload + atom("moov", audioTrack + chapterTrack))
        assertEquals(listOf("One", "Two"), result.chapters.map { it.title }); assertEquals(15000L, result.chapters.last().startMs)
    }
    @Test fun readsId3SeriesAndChapterFrames() {
        fun frame(name: String, bytes: ByteArray) = name.toByteArray() + number(bytes.size) + byteArrayOf(0, 0) + bytes
        val fields = frame("TXXX", byteArrayOf(3) + "SERIES\u0000A series".toByteArray()) + frame("TXXX", byteArrayOf(3) + "SERIES-PART\u00002".toByteArray())
        val chapter = frame("CHAP", "c1\u0000".toByteArray() + number(0) + number(30000) + number(-1) + number(-1) + frame("TIT2", byteArrayOf(3) + "Opening".toByteArray()))
        val tag = fields + chapter; val n = tag.size
        val size = byteArrayOf(((n shr 21) and 127).toByte(), ((n shr 14) and 127).toByte(), ((n shr 7) and 127).toByte(), (n and 127).toByte())
        val result = read("ID3".toByteArray() + byteArrayOf(3, 0, 0) + size + tag)
        assertEquals("A series", result.series); assertEquals(2.0, result.order, 0.0); assertEquals("Opening", result.chapters.single().title)
    }
    @Test fun readsCueSidecarAndRejectsUnknownSources() {
        val source = JSONObject().put("id", "a").put("filename", "Book.mp3").put("durationMs", 30000)
        val text = "FILE \"Book.mp3\" MP3\n TRACK 01 AUDIO\n TITLE \"One\"\n INDEX 01 00:00:00\n TRACK 02 AUDIO\n TITLE \"Two\"\n INDEX 01 00:15:00"
        val result = AudioCueChapters.parse(text, listOf(source)); assertEquals(2, result.length()); assertEquals(15000L, result.getJSONObject(0).getLong("endMs"))
        assertThrows(IllegalArgumentException::class.java) { AudioCueChapters.parse(text.replace("Book.mp3", "Missing.mp3"), listOf(source)) }
    }
}
