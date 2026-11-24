package com.dividetask.crimsonsteel.net

import com.dividetask.crimsonsteel.data.AppRelease

/** Comparing this app's build with the server's (docs/project/app_updates.md). No Android classes: unit-tested. */
object AppVersions {
    /** The version part of a version name: "v0.036 a (cb86)" → (0, 36). */
    fun parse(v: String?): Pair<Int, Int>? =
        v?.let { Regex("v(\\d+)\\.(\\d+)").find(it) }?.let { Pair(it.groupValues[1].toInt(), it.groupValues[2].toInt()) }

    fun compare(a: Pair<Int, Int>, b: Pair<Int, Int>) = compareValuesBy(a, b, { it.first }, { it.second })

    /** The commit this app was built from: the "(7bca)" in "v0.039 a (7bca)". */
    fun commitOf(versionName: String?): String? =
        versionName?.let { Regex("\\(([0-9a-f]{4,})\\)").find(it)?.groupValues?.get(1) }

    /**
     * The server's build must be installed: it was built from another commit
     * and is not an older version. A server-only commit still makes a new APK
     * whose version name repeats the last number, so the commit decides.
     */
    fun needsUpdate(server: AppRelease?,
                    mine: String = runCatching { com.dividetask.crimsonsteel.BuildConfig.VERSION_NAME }.getOrDefault("")): Boolean {
        val theirs = parse(server?.version) ?: return false
        val own = parse(mine) ?: return false
        val myCommit = commitOf(mine)
        val serverCommit = server?.commit
        if (myCommit != null && serverCommit != null) {
            return !serverCommit.startsWith(myCommit) && compare(theirs, own) >= 0
        }
        return compare(theirs, own) > 0
    }
}
