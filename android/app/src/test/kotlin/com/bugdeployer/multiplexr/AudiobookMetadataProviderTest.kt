package com.bugdeployer.multiplexr

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AudiobookMetadataProviderTest {
    @Test fun searchRetainsFirstBookBeyondOldTenResultLimit() {
        val products = org.json.JSONArray()
        for (i in 2..13) products.put(JSONObject().put("asin", "B" + i.toString().padStart(9, '0')).put("title", "The Primal Hunter $i"))
        products.put(JSONObject().put("asin", "B09MWP4277").put("title", "The Primal Hunter"))
        val found = AudiobookMetadataProvider.searchResults(products)
        assertEquals(13, found.length())
        assertEquals("B09MWP4277", found.getJSONObject(12).getString("providerId"))
    }

    @Test fun audiobookSpecificMetadataIncludesNarratorAndSquareCover() {
        val value = AudiobookMetadataProvider.normalize(JSONObject("""{
          "asin":"0008433844","title":"The Hobbit","authors":[{"name":"J.R.R. Tolkien"}],
          "narrators":[{"name":"Andy Serkis"}],"series":[{"asin":"B009","title":"Middle-earth","sequence":"0.5"}],
          "product_images":{"100":"https://m.media-amazon.com/images/small.jpg","500":"https://m.media-amazon.com/images/large.jpg"},
          "merchandising_summary":"<p>A story &amp; adventure.</p>","runtime_length_min":640
        }"""))
        assertEquals("Andy Serkis", value.getString("narrator"))
        assertEquals("audible:B009", value.getString("seriesId"))
        assertEquals(0.5, value.getDouble("seriesOrder"), 0.0)
        assertEquals("A story & adventure.", value.getString("description"))
        assertEquals("https://m.media-amazon.com/images/large.jpg", value.getString("coverUrl"))
        assertEquals("audible", value.getString("metadataSource"))
    }
    @Test fun coverDownloadsUseKnownHttpsImageHosts() {
        assertTrue(AudiobookMetadataProvider.allowedCover("https://m.media-amazon.com/images/cover.jpg"))
        for (url in listOf("http://m.media-amazon.com/a", "https://m.media-amazon.com.evil.test/a", "file:///etc/passwd", "https://user@m.media-amazon.com/a")) {
            assertFalse(AudiobookMetadataProvider.allowedCover(url))
        }
    }
}
