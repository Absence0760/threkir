package com.runapp.watchwear

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/// Every `event_results` write and delete the watch makes for a race, in one
/// order. A finish is banked to [store] before it is sent, so one with no
/// signal is replayed off the race poll; a finish the runner withdrew ("Not
/// finished? Resume", #1307 m11) is deleted, or remembered as a void when
/// there is no signal and deleted before any later result for that race.
///
/// One lock covers all of it, so an undo waits for a filing in flight and no
/// replay can send the withdrawn finish again behind the delete.
///
/// A [CancellationException] is never a send failure: it carries no HTTP
/// status, so [isRetryableRaceResultFailure] would call it retryable, and the
/// store writes after it would throw again in the cancelled coroutine. Every
/// catch below rethrows it first.
internal class RaceResultOutbox(
    private val store: RaceResultStore,
    private val submit: suspend (token: String, result: PendingRaceResult) -> Unit,
    private val deleteAuto: suspend (token: String, userId: String, eventId: String, instanceStart: String) -> Unit,
    private val onFailure: (String, Throwable) -> Unit,
) {
    private val lock = Mutex()

    /// Bank [result], then send it when there is a token. A failure to send
    /// leaves it queued, unless the server refused the body outright.
    suspend fun file(token: String?, result: PendingRaceResult) = lock.withLock {
        try {
            store.add(result)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            onFailure("race result not persisted; it is sent once without a retry net", e)
        }
        if (token != null) send(token, result)
    }

    /// Send every result queued for [userId]: never another account's.
    suspend fun replay(token: String, userId: String) = lock.withLock {
        try {
            for (v in store.voids().filter { it.userId == userId }) flushVoid(token, v)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            onFailure("pending race voids not flushed", e)
        }
        val pending = try {
            store.current()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            onFailure("pending race results unreadable", e)
            return@withLock
        }
        for (r in raceResultsToReplay(pending, userId)) send(token, r)
    }

    /// Withdraw [userId]'s automatic finish for one race: drop it from the
    /// queue and delete the filed row while it is still the runner's own
    /// `auto` one. With no signal (or no token) the delete is kept as a void.
    suspend fun void(token: String?, userId: String, eventId: String, instanceStart: String) = lock.withLock {
        try {
            store.dequeue(userId, eventId, instanceStart)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            onFailure("withdrawn race finish not dropped from the queue", e)
        }
        val v = PendingRaceVoid(userId, eventId, instanceStart)
        if (token == null) {
            keepVoid(v)
            return@withLock
        }
        try {
            deleteAuto(token, userId, eventId, instanceStart)
        } catch (e: CancellationException) {
            keepVoid(v)
            throw e
        } catch (e: Throwable) {
            if (isRetryableRaceResultFailure(e)) {
                onFailure("withdrawn race finish not deleted; kept for the next poll", e)
                keepVoid(v)
            } else {
                onFailure("withdrawn race finish refused by the server", e)
            }
        }
    }

    /// The finish has already left the queue by now, so the void is written even
    /// when the caller was cancelled mid-delete: losing it would leave the
    /// withdrawn finish on the board with nothing left to delete it.
    private suspend fun keepVoid(v: PendingRaceVoid) = withContext(NonCancellable) {
        try {
            store.addVoid(v)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            onFailure("withdrawn race finish not remembered; the row may stay", e)
        }
    }

    /// Delete a withdrawn finish. Throws when the delete fails for a reason
    /// worth retrying, so the result behind it waits too.
    private suspend fun flushVoid(token: String, v: PendingRaceVoid) {
        try {
            deleteAuto(token, v.userId, v.eventId, v.instanceStart)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            if (isRetryableRaceResultFailure(e)) throw e
            onFailure("withdrawn race finish refused by the server; dropping the void", e)
        }
        store.removeVoid(v)
    }

    private suspend fun send(token: String, result: PendingRaceResult) {
        val sent = try {
            store.voids()
                .firstOrNull {
                    it.userId == result.userId && it.eventId == result.eventId &&
                        it.instanceStart == result.instanceStart
                }
                ?.let { flushVoid(token, it) }
            submit(token, result)
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            if (isRetryableRaceResultFailure(e)) {
                onFailure("race result not sent; kept for the next race poll", e)
                return
            }
            onFailure("race result refused by the server; dropping it", e)
            false
        }
        try {
            store.remove(result)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            onFailure("race result queue not trimmed (sent=$sent); a replay is an idempotent upsert", e)
        }
    }
}
