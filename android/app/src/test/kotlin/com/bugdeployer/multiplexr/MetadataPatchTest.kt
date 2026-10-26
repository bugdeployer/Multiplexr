package com.bugdeployer.multiplexr
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
class MetadataPatchTest {
    @Test fun providerPatchFreezesExistingStructuralAnchor() {
        val patch = JSONObject("""{"fields":{"metadata.title":"New"},"expected":{"metadata.title":"Old"},"groupAnchor":"local:root:show"}""")
        val first = MetadataPatch.apply(current(), patch)
        assertEquals("local:root:show", first.getJSONObject("metadata").getString("structuralSeriesId"))
        patch.put("groupAnchor", "tmdb:other")
        assertEquals("local:root:show", MetadataPatch.apply(first, patch).getJSONObject("metadata").getString("structuralSeriesId"))
    }
    private fun current() = JSONObject("""{"id":"a","metadata":{"title":"Old","tags":"keep","groupId":"manual","series":"Curated"},"positionMs":1234,"poster":"old","localPoster":"cached","providerId":1}""")
    @Test fun selectedPatchPreservesUnrelatedMetadataAndProgress() {
        val value = MetadataPatch.apply(current(), JSONObject("""{"fields":{"metadata.title":"New","providerId":2},"expected":{"metadata.title":"Old","providerId":1}}"""))
        assertEquals("New",value.getJSONObject("metadata").getString("title"))
        assertEquals("keep",value.getJSONObject("metadata").getString("tags"))
        assertEquals(1234,value.getInt("positionMs"))
    }
    @Test(expected=MetadataConflict::class) fun changedSelectedFieldRejectsWholePatch() {
        MetadataPatch.apply(current().apply { getJSONObject("metadata").put("title","Manual edit") }, JSONObject("""{"fields":{"metadata.title":"New","providerId":2},"expected":{"metadata.title":"Old","providerId":1}}"""))
    }
    @Test fun repeatApplyIsIdempotentAndInvalidatesOnlyChangedArtworkCache() {
        val patch=JSONObject("""{"fields":{"poster":"new"},"expected":{"poster":"old"}}""")
        val first=MetadataPatch.apply(current(),patch)
        assertTrue(first.isNull("localPoster"))
        assertEquals(first.toString(),MetadataPatch.apply(first,patch).toString())
    }
    @Test fun seriesPosterDoesNotChangeEpisodePosterOrGrouping() {
        val value=MetadataPatch.apply(current(),JSONObject("""{"fields":{"metadata.seriesPoster":"series-cover","metadata.series":"Provider name"},"expected":{"metadata.seriesPoster":null,"metadata.series":"Curated"}}"""))
        assertEquals("old",value.getString("poster"))
        assertEquals("cached",value.getString("localPoster"))
        assertEquals("Curated",value.getJSONObject("metadata").getString("series"))
    }
    @Test(expected=IllegalArgumentException::class) fun sourceMutationIsNotAMetadataAction() {
        MetadataPatch.apply(current(),JSONObject("""{"fields":{"uri":"new"},"expected":{"uri":null}}"""))
    }
    @Test(expected=MetadataConflict::class) fun statusCannotClobberAnInterveningManualEdit() {
        val value=current().put("metadataSource","manual")
        MetadataPatch.apply(value,JSONObject("""{"fields":{"metadataStatus":"review"},"expected":{"metadataStatus":null,"metadataSource":"filename"}}"""))
    }
    @Test fun freshScanProjectionSurvivesSelectiveApply() {
        val value=JSONObject("""{"id":"fresh","filename":"Film.2020.mp4","positionMs":15}""")
        val patch=JSONObject("""{"fields":{"metadata.description":"Summary","metadataSource":"tmdb","providerId":1},"expected":{"metadata.description":null,"metadataSource":"filename","providerId":null,"filename":"Film.2020.mp4","relativePath":"","rootUri":""},"inferred":{"title":"Film","year":"2020"}}""")
        val updated=MetadataPatch.apply(value,patch)
        assertEquals("Film",updated.getJSONObject("metadata").getString("title"))
        assertEquals("2020",updated.getJSONObject("metadata").getString("year"))
        assertEquals("Summary",updated.getJSONObject("metadata").getString("description"))
        assertEquals(15,updated.getInt("positionMs"))
    }
    @Test fun seriesJobIsOwnedByExactCollection() {
        val key="metadata:series:[\"c:a\",\"local:series\"]"
        assertTrue(CollectionStatePolicy.ownedBy(key,"c:a"))
        assertFalse(CollectionStatePolicy.ownedBy(key,"c"))
        assertFalse(CollectionStatePolicy.exportable(key))
    }
}
