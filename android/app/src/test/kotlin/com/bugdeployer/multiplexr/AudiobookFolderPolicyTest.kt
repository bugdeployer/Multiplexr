package com.bugdeployer.multiplexr
import org.junit.Assert.*
import org.junit.Test

class AudiobookFolderPolicyTest {
    @Test fun agreedHierarchySupportsOneM4bOrManyMp3s() {
        assertNull(AudiobookFolderPolicy.issue(2, listOf("Book.m4b"), listOf(""), false))
        assertNull(AudiobookFolderPolicy.issue(2, listOf("01.mp3", "02.mp3"), listOf("", ""), false))
    }
    @Test fun nestedDiscFoldersAreReportedInsteadOfBecomingSeparateBooks() {
        assertNotNull(AudiobookFolderPolicy.issue(3, listOf("01.mp3"), listOf(""), false))
    }
    @Test fun unrelatedLooseAudioAndMultipleUnidentifiedM4bsNeedCorrection() {
        assertNotNull(AudiobookFolderPolicy.issue(0, listOf("a.mp3", "b.mp3"), listOf("A", "B"), false))
        assertNotNull(AudiobookFolderPolicy.issue(1, listOf("a.m4b", "b.m4b"), listOf("", ""), false))
    }
    @Test fun legacyBookFoldersAndIndividuallyIdentifiedRootM4bsStillWork() {
        assertNull(AudiobookFolderPolicy.issue(1, listOf("01.mp3", "02.mp3"), listOf("", ""), false))
        assertNull(AudiobookFolderPolicy.issue(0, listOf("Book.m4b"), listOf(""), true))
        assertNull(AudiobookFolderPolicy.issue(0, listOf("01.mp3", "02.mp3"), listOf("Same", "Same"), false))
    }
    @Test fun mixedAudioAndBookSubfoldersAreNotSilentlyCombined() {
        assertNotNull(AudiobookFolderPolicy.issue(1, listOf("01.mp3"), listOf(""), true))
    }
}
