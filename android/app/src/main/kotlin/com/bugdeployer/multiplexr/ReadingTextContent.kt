package com.bugdeployer.multiplexr

import java.io.ByteArrayInputStream
import javax.xml.parsers.SAXParserFactory
import org.xml.sax.Attributes
import org.xml.sax.helpers.DefaultHandler
import org.json.JSONArray
import org.json.JSONObject

/** Frozen normalization v1: canonical UTF-16 offsets, never screen coordinates. */
object ReadingTextContent {
    const val MAX_CHARACTERS = 8 * 1024 * 1024
    data class Content(val text: String, val anchors: Map<String, Int>, val styles: List<JSONObject>, val elements: List<JSONObject> = emptyList()) {
        fun json() = JSONObject().put("version", 1).put("text", text).put("anchors", JSONObject(anchors)).put("styles", JSONArray(styles)).put("elements", JSONArray(elements))
    }
    fun plain(bytes: ByteArray, encoding: String): Content {
        require(bytes.size <= 16 * 1024 * 1024)
        require(encoding in setOf("utf-8", "utf-16le", "utf-16be", "windows-1252"))
        val decoder = charset(encoding).newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT).onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
        val text = decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString().removePrefix("\uFEFF").replace("\r\n", "\n").replace('\r', '\n')
        require(text.length <= MAX_CHARACTERS && !text.contains('\u0000'))
        return Content(text, emptyMap(), emptyList())
    }
    internal fun sanitizedXml(bytes: ByteArray): String {
        require(bytes.size <= 32 * 1024 * 1024 && !bytes.contains(0))
        val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
        val input = decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString()
        require(!Regex("<!\\s*ENTITY", RegexOption.IGNORE_CASE).containsMatchIn(input)) { "External entities are not supported." }
        val declarations = Regex("<!DOCTYPE[^>]*>", RegexOption.IGNORE_CASE).findAll(input).toList()
        require(declarations.none { it.value.contains('[') }) { "Internal DTDs are not supported." }
        // Accept ordinary EPUB XHTML doctypes without resolving their external DTD.
        val safe = Regex("<!DOCTYPE[^>]*>", RegexOption.IGNORE_CASE).replace(input, "")
        require(!Regex("<!\\s*DOCTYPE", RegexOption.IGNORE_CASE).containsMatchIn(safe))
        return safe
    }
    fun xhtml(bytes: ByteArray): Content {
        val safe = sanitizedXml(bytes)
        val output = StringBuilder(); val anchors = linkedMapOf<String, Int>(); val styles = mutableListOf<JSONObject>()
        val elements = mutableListOf<JSONObject>()
        val links = java.util.ArrayDeque<Pair<Int, String>>()
        val stack = java.util.ArrayDeque<Triple<String, Int, String?>>()
        var skip = 0; var pendingSpace = false; var pre = 0
        fun newline() { pendingSpace = false; if (output.isNotEmpty() && output.last() != '\n') output.append('\n') }
        val blocks = setOf("p", "div", "section", "article", "blockquote", "li", "pre", "h1", "h2", "h3", "h4", "h5", "h6")
        val handler = object : DefaultHandler() {
            override fun resolveEntity(publicId: String?, systemId: String?): org.xml.sax.InputSource = throw IllegalArgumentException("External entities are disabled")
            override fun startElement(uri: String?, local: String?, qName: String?, attributes: Attributes) {
                val name = (local?.ifEmpty { qName.orEmpty() } ?: qName.orEmpty()).substringAfter(':').lowercase()
                if (skip > 0 || name in setOf("head", "script", "style", "noscript", "iframe", "object", "svg")) { skip++; return }
                if (name in blocks) { newline(); if (output.isNotEmpty()) output.append('\n') }
                if (name == "br") newline()
                if (name == "pre") pre++
                if (name == "li") output.append("• ")
                if (pendingSpace && output.isNotEmpty() && !output.last().isWhitespace()) output.append(' ')
                pendingSpace = false
                val id = attributes.getValue("id") ?: attributes.getValue("xml:id")
                if (!id.isNullOrEmpty()) { require(id.length <= 4096 && anchors.size < 100000); anchors.putIfAbsent(id, output.length) }
                if (name == "a") links.addLast(output.length to (attributes.getValue("href") ?: ""))
                if (name == "img") {
                    val src = attributes.getValue("src").orEmpty()
                    if (src.length in 1..4096 && elements.size < 10000) elements.add(JSONObject().put("kind", "image").put("offset", output.length).put("href", src).put("label", attributes.getValue("alt").orEmpty().take(4096)))
                }
                val style = when (name) { "strong", "b" -> "bold"; "em", "i" -> "italic"; "h1", "h2", "h3", "h4", "h5", "h6" -> "heading"; "pre", "code" -> "code"; "blockquote" -> "quote"; else -> null }
                stack.addLast(Triple(name, output.length, style))
                if (name == "img") attributes.getValue("alt")?.takeIf { it.isNotBlank() }?.let { output.append("[$it]") }
            }
            override fun characters(chars: CharArray, start: Int, length: Int) {
                if (skip > 0) return
                for (i in start until start + length) {
                    val ch = chars[i]
                    if (pre == 0 && ch.isWhitespace()) { pendingSpace = true; continue }
                    if (pendingSpace && output.isNotEmpty() && !output.last().isWhitespace()) output.append(' ')
                    pendingSpace = false; output.append(ch)
                }
                require(output.length <= MAX_CHARACTERS) { "Text resource exceeds reader capacity." }
            }
            override fun endElement(uri: String?, local: String?, qName: String?) {
                if (skip > 0) { skip--; return }
                val (name, start, style) = stack.removeLast()
                if (style != null && start < output.length) { require(styles.size < 100000); styles.add(JSONObject().put("start", start).put("end", output.length).put("kind", style)) }
                if (name == "a" && links.isNotEmpty()) {
                    val (offset, href) = links.removeLast()
                    if (href.length in 1..4096 && elements.size < 10000) elements.add(JSONObject().put("kind", "link").put("offset", offset).put("href", href).put("label", output.substring(offset).take(4096)))
                }
                if (name == "pre") pre--
                if (name in blocks) newline()
            }
        }
        val factory = SAXParserFactory.newInstance().apply {
            isNamespaceAware = true
            runCatching { setFeature("http://xml.org/sax/features/external-general-entities", false) }
            runCatching { setFeature("http://xml.org/sax/features/external-parameter-entities", false) }
            runCatching { setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false) }
        }
        factory.newSAXParser().parse(ByteArrayInputStream(safe.toByteArray(Charsets.UTF_8)), handler)
        require(output.length <= MAX_CHARACTERS)
        return Content(output.toString(), anchors, styles, elements)
    }
}
