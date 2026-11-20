package com.runapp.watchwear

import java.io.File
import java.nio.file.Files
import java.util.zip.GZIPInputStream
import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Pin the URLs + bodies the watch's [SupabaseClient] sends. A typo
/// in the query string (wrong filter, dropped sort, missing limit)
/// would silently change which routes appear on the watch picker
/// or how the refresh-token grant is routed — both load-bearing for
/// daily use.
class SupabaseUrlBuildersTest {

    // ───────────── fetchRoutes URL strings ─────────────

    private val uid = "8d3b2a10-0000-4000-8000-000000000001"
    private val starred = fetchRoutesStarredQuery(uid)
    private val fallback = fetchRoutesFallbackQuery(uid)

    @Test fun `starred query selects the right columns and filters`() {
        // The watch picker needs id (for the deep-link), name (for
        // the chip label), waypoints (rendered as the polyline +
        // off-route math), and distance_m (the chip's secondary
        // label). Any other column would just bloat the wire.
        assertTrue(starred.contains("select=id,name,waypoints,distance_m"))
        // Starred-only filter — without `is_starred=eq.true` we'd
        // be back at the old behaviour of pulling 30 most-recent
        // routes, defeating the curation feature.
        assertTrue(starred.contains("is_starred=eq.true"))
        // Most-recent first so the runner's latest curation lands
        // at the top of the picker.
        assertTrue(starred.contains("order=updated_at.desc"))
        // Cap at 30 — pinned so a future "let's show 100" change
        // requires a test edit + thinks about the 1.4-inch UX.
        assertTrue(starred.contains("limit=30"))
    }

    @Test fun `both queries read only the signed-in runner's own routes`() {
        // RLS returns a club route to every member, and `is_starred` is
        // the owner's curation: without the owner filter a route a club
        // admin starred reaches a member's wrist with its raw waypoints,
        // past the privacy-zone clipping (decisions § 33). The phone's
        // `routesVisibleToWatch` holds the same rule.
        for (q in listOf(starred, fallback)) {
            val params = q.split("&")
            assertTrue(q, params.contains("user_id=eq.$uid"))
        }
    }

    @Test fun `the owner filter cannot be widened by the id it is given`() {
        // A user id is a UUID from GoTrue, but the builder still encodes
        // it, so a value carrying `&` or `,` could never add a predicate.
        val q = fetchRoutesStarredQuery("a&is_starred=eq.false,b")
        assertEquals(1, q.split("&").count { it.startsWith("is_starred=") })
        assertTrue(q.contains("user_id=eq.a%26is_starred%3Deq.false%2Cb&"))
    }

    @Test fun `fallback query omits the starred filter, caps tighter`() {
        // Without the `is_starred=eq.true` predicate this falls back
        // to "all owned routes". Capped tighter (10) than the
        // starred path because this is undirected — better to show
        // too few than stale GPX imports.
        assertEquals(false, fallback.contains("is_starred"))
        assertTrue(fallback.contains("order=updated_at.desc"))
        assertTrue(fallback.contains("limit=10"))
        assertTrue(fallback.contains("select=id,name,waypoints,distance_m"))
    }

    @Test fun `chooseFirstRoutesQuery returns the starred predicate`() {
        // Pin the decision: the FIRST attempt is always starred-only.
        assertEquals(starred, chooseFirstRoutesQuery(uid))
    }

    @Test fun `chooseFallbackRoutesQuery returns the recent-routes predicate`() {
        // Pin the decision: the SECOND attempt (when starred is
        // empty) is recent-routes.
        assertEquals(fallback, chooseFallbackRoutesQuery(uid))
    }

    @Test fun `buildFetchRoutesUrl composes base + query string`() {
        val out = buildFetchRoutesUrl(
            baseUrl = "https://x.supabase.co",
            query = starred,
        )
        assertEquals(
            "https://x.supabase.co/rest/v1/routes?$starred",
            out,
        )
    }

    @Test fun `buildFetchRoutesUrl handles local-emulator base URL`() {
        // 10.0.2.2 is the Android emulator's loopback alias for the
        // host machine — what the watch hits against a local
        // Supabase stack. Make sure the URL composer doesn't
        // mangle the IPv4 numeric form.
        val out = buildFetchRoutesUrl(
            baseUrl = "http://10.0.2.2:24321",
            query = "anything",
        )
        assertEquals("http://10.0.2.2:24321/rest/v1/routes?anything", out)
    }

    // ───────────── refreshAccessToken wire shape ─────────────

    @Test fun `refresh body carries only refresh_token`() {
        // Critical security property: the refresh body must NEVER
        // include the current access token. Doing so would leak it
        // through proxy logs, and the access token is the thing
        // we're trying to REPLACE. Pin the single-key body.
        val out = buildRefreshTokenBody("rt-abc")
        assertEquals("""{"refresh_token":"rt-abc"}""", out)
    }

    @Test fun `refresh body escapes embedded quotes in the token`() {
        // A bogus / corrupted refresh token shouldn't crash the
        // JSON encoder. JsonObject handles escaping correctly.
        val out = buildRefreshTokenBody("""rt"with"quotes""")
        assertEquals("""{"refresh_token":"rt\"with\"quotes"}""", out)
    }

    @Test fun `refresh URL includes the grant_type query string`() {
        // GoTrue's `/auth/v1/token` endpoint multiplexes on
        // `grant_type` — refresh_token vs password. Missing the
        // query string misroutes the request to password-grant
        // where it 400s on the missing email+password fields.
        val out = buildRefreshTokenUrl("https://x.supabase.co")
        assertEquals(
            "https://x.supabase.co/auth/v1/token?grant_type=refresh_token",
            out,
        )
    }

    @Test fun `refresh URL with local-emulator base composes cleanly`() {
        val out = buildRefreshTokenUrl("http://10.0.2.2:24321")
        assertEquals(
            "http://10.0.2.2:24321/auth/v1/token?grant_type=refresh_token",
            out,
        )
    }

    // ───────────── computeRefreshExpiryMs ─────────────

    @Test fun `expiry uses GoTrue expires_in directly when present`() {
        // GoTrue returns `expires_in: 3600` for a 1-hour token.
        // Convert to absolute ms-from-epoch added to nowMs.
        val nowMs = 1_700_000_000_000L
        val out = computeRefreshExpiryMs(nowMs, expiresInSec = 3600L)
        assertEquals(nowMs + 3_600_000L, out)
    }

    @Test fun `expiry falls back to 1 hour when expires_in is null`() {
        // Defensive: GoTrue ALWAYS includes expires_in, but a
        // future server change shouldn't break the watch's
        // expiry tracking. Default to the historical 1-hour token
        // lifetime so the watch still knows when to refresh.
        val nowMs = 1_700_000_000_000L
        val out = computeRefreshExpiryMs(nowMs, expiresInSec = null)
        assertEquals(nowMs + 3_600_000L, out)
    }

    @Test fun `expiry honours short-lived tokens (60 sec edge case)`() {
        // GoTrue's `jwt_exp` config can be set as low as 60 s for
        // testing. Confirm the math works without overflow / loss.
        val nowMs = 0L
        val out = computeRefreshExpiryMs(nowMs, expiresInSec = 60L)
        assertEquals(60_000L, out)
    }

    @Test fun `expiry honours long-lived tokens (1 week edge case)`() {
        // Some self-hosted Supabase deployments use week-long
        // tokens. Confirm no overflow.
        val nowMs = 1_700_000_000_000L
        val weekSec = 7L * 24 * 3600
        val out = computeRefreshExpiryMs(nowMs, expiresInSec = weekSec)
        assertEquals(nowMs + weekSec * 1000L, out)
    }

    // ───────────── uploadTrack idempotency (issue #455) ─────────────

    @Test fun `uploadTrack request carries x-upsert true so a retry overwrites instead of 409`() {
        // The track object is keyed deterministically at
        // {uid}/{runId}.json.gz. If saveRun's row POST fails after
        // the track uploaded, drainQueue re-runs uploadTrack against
        // an object that already exists. Without `x-upsert: true`
        // Storage returns 409 Duplicate, execute() throws, and the
        // run wedges the queue forever. The header is the fix.
        val req = uploadRequestFor(gzippedTrack())
        assertEquals("true", req.header("x-upsert"))
    }

    @Test fun `uploadTrack request targets the runs bucket via POST with auth`() {
        val req = uploadRequestFor(gzippedTrack())
        assertEquals("POST", req.method)
        assertEquals(
            "https://x.supabase.co/storage/v1/object/runs/user-1/run-1.json.gz",
            req.url.toString(),
        )
        assertEquals("anon", req.header("apikey"))
        assertEquals("Bearer tok", req.header("Authorization"))
    }

    // ───────────── uploadTrack content type (issue #1073) ─────────────

    @Test fun `uploadTrack sends gzip as the body's own media type, not only as a header`() {
        // The `runs` bucket's allowed_mime_types refuses application/json
        // with `invalid_mime_type`, which is how every watch-recorded run
        // sat at "can't sync". OkHttp puts the BODY's media type on the
        // wire, so a header-only assertion passes against a request that
        // still sends application/json — read the body's.
        val req = uploadRequestFor(gzippedTrack())
        assertEquals("application/gzip", req.body?.contentType()?.toString())
        assertEquals("application/gzip", req.header("Content-Type"))
        assertEquals(TRACK_UPLOAD_CONTENT_TYPE, req.body?.contentType()?.toString())
        // The object is a gzip file, not a gzip-encoded JSON entity.
        assertNull(req.header("Content-Encoding"))
    }

    @Test fun `uploadTrack body is the gzipped track json`() {
        val json = """[{"lat":51.5,"lng":-0.12,"t":1700000000000}]"""
        val req = uploadRequestFor(gzippedTrack(json))
        val bytes = Buffer().also { req.body!!.writeTo(it) }.readByteArray()
        assertEquals(0x1f.toByte(), bytes[0])
        assertEquals(0x8b.toByte(), bytes[1])
        assertEquals(json, GZIPInputStream(bytes.inputStream()).readBytes().decodeToString())
    }

    private fun gzippedTrack(json: String = "[]"): File {
        val dir = Files.createTempDirectory("track_upload_test").toFile().apply { deleteOnExit() }
        val track = File(dir, "run-1.json").apply { writeText(json) }
        return gzipTrackToTempFile(track).apply { deleteOnExit() }
    }

    private fun uploadRequestFor(gzFile: File) = buildUploadTrackRequest(
        baseUrl = "https://x.supabase.co",
        path = "user-1/run-1.json.gz",
        anonKey = "anon",
        token = "tok",
        gzFile = gzFile,
    )
}
