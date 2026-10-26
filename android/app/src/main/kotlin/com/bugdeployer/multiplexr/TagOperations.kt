package com.bugdeployer.multiplexr

object TagOperations {
    fun normalize(values: List<*>): List<String> {
        val seen = mutableSetOf<String>()
        return values.flatMap { it.toString().split(',', ';') }.map { it.trim().trimStart('#').trim() }
            .filter { it.isNotEmpty() && seen.add(it.lowercase(java.util.Locale.ROOT)) }.also {
                require(it.size <= 100 && it.all { tag -> tag.length <= 80 }) { "Use at most 100 tags of 80 characters each." }
            }
    }
    fun apply(existing: String, operation: String, tags: List<String>, target: String?): List<String> {
        val current = normalize(listOf(existing))
        val keys = tags.map { it.lowercase(java.util.Locale.ROOT) }.toSet()
        return when (operation) {
            "replace" -> tags
            "add" -> normalize(current + tags)
            "remove", "delete" -> current.filter { it.lowercase(java.util.Locale.ROOT) !in keys }
            "rename" -> {
                require(tags.size == 1 && !target.isNullOrBlank())
                val replacement = normalize(listOf(target)); require(replacement.size == 1)
                val mergedName = current.firstOrNull { it.equals(replacement.single(), true) } ?: replacement.single()
                normalize(current.map { if (it.equals(tags.single(), true)) mergedName else it })
            }
            else -> error("Unknown tag operation")
        }
    }
}
