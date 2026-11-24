package com.dividetask.crimsonsteel.net

import com.dividetask.crimsonsteel.data.AppRelease
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppVersionsTest {
    @Test fun readsTheCommitFromTheVersionName() {
        assertEquals("7bca", AppVersions.commitOf("v0.039 a (7bca)"))
        assertEquals(null, AppVersions.commitOf("v0.039 a (unknown)"))
    }

    @Test fun sameBuildIsUpToDate() {
        assertFalse(AppVersions.needsUpdate(AppRelease("v0.039", "e04095d"), "v0.039 a (e040)"))
    }

    @Test fun aServerOnlyCommitsApkIsStillAnUpdate() {
        // v0.040.apk built from 7bcaba1 calls itself v0.039 a (7bca).
        assertTrue(AppVersions.needsUpdate(AppRelease("v0.040", "7bcaba1"), "v0.039 a (e040)"))
        assertFalse(AppVersions.needsUpdate(AppRelease("v0.040", "7bcaba1"), "v0.039 a (7bca)"))
    }

    @Test fun neverAnOlderBuild() {
        assertFalse(AppVersions.needsUpdate(AppRelease("v0.037", "3471632"), "v0.039 a (e040)"))
    }

    @Test fun withoutCommitsComparesNumbers() {
        assertTrue(AppVersions.needsUpdate(AppRelease("v0.040", null), "v0.039 a (e040)"))
        assertFalse(AppVersions.needsUpdate(AppRelease("v0.039", null), "v0.039 a (e040)"))
        assertFalse(AppVersions.needsUpdate(null, "v0.039 a (e040)"))
    }
}
