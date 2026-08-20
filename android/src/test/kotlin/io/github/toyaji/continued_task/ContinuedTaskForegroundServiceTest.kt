package io.github.toyaji.continued_task

import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Verifies foreground service branching logic on the JVM using Robolectric.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ContinuedTaskForegroundServiceTest {

    private lateinit var events: MutableList<String>
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        events = mutableListOf()
        ContinuedTaskForegroundService.eventListener = { events.add(it) }
        clearStopRequestFlag()
    }

    @After
    fun tearDown() {
        ContinuedTaskForegroundService.eventListener = null
        clearStopRequestFlag()
    }

    private fun clearStopRequestFlag() {
        context.getSharedPreferences(
            ContinuedTaskForegroundService.PREFS_NAME, Context.MODE_PRIVATE
        ).edit().remove(ContinuedTaskForegroundService.KEY_STOP_REQUESTED).apply()
    }

    private fun stopRequestFlag(): Boolean = context.getSharedPreferences(
        ContinuedTaskForegroundService.PREFS_NAME, Context.MODE_PRIVATE
    ).getBoolean(ContinuedTaskForegroundService.KEY_STOP_REQUESTED, false)

    private fun buildService(): ContinuedTaskForegroundService =
        Robolectric.buildService(ContinuedTaskForegroundService::class.java).create().get()

    private fun intent(action: String): Intent =
        Intent(context, ContinuedTaskForegroundService::class.java).setAction(action)

    // ─────────────────────────── Lifecycle Assertion ───────────────────────────

    @Test
    fun `START acquires assertion and notifies listeners`() {
        val service = buildService()

        service.onStartCommand(
            intent(ContinuedTaskForegroundService.ACTION_START)
                .putExtra(ContinuedTaskForegroundService.EXTRA_TITLE, "Test")
                .putExtra(ContinuedTaskForegroundService.EXTRA_MAX_PROGRESS, 10),
            0,
            1
        )

        assertTrue(ContinuedTaskForegroundService.isAssertionHeld)
        assertEquals(listOf("assertionAcquired"), events)
    }

    @Test
    fun `STOP releases assertion and notifies listeners`() {
        val service = buildService()
        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_START), 0, 1)
        events.clear()

        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_STOP), 0, 2)

        assertFalse(ContinuedTaskForegroundService.isAssertionHeld)
        assertEquals(listOf("assertionLost"), events)
    }

    @Test
    fun `unknown action stops the service`() {
        val service = buildService()

        service.onStartCommand(intent("io.github.toyaji.continued_task.UNKNOWN"), 0, 1)

        assertFalse(ContinuedTaskForegroundService.isAssertionHeld)
        assertTrue(events.contains("assertionLost"))
    }

    @Test
    fun `service returns START_NOT_STICKY so it is not recreated on crash`() {
        val service = buildService()

        val result = service.onStartCommand(
            intent(ContinuedTaskForegroundService.ACTION_START), 0, 1
        )

        assertEquals(android.app.Service.START_NOT_STICKY, result)
    }

    // ─────────────────────── User Cancel Action ───────────────────────

    @Test
    fun `USER_CANCEL dispatches event immediately when Dart listener is attached`() {
        val service = buildService()

        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_USER_CANCEL), 0, 1)

        assertEquals(listOf("stopRequested"), events)
        assertFalse(stopRequestFlag())
    }

    @Test
    fun `USER_CANCEL records flag and stops service when Dart listener is detached`() {
        ContinuedTaskForegroundService.eventListener = null
        val service = buildService()

        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_USER_CANCEL), 0, 1)

        assertTrue(stopRequestFlag())
        assertFalse(ContinuedTaskForegroundService.isAssertionHeld)
    }

    // ─────────────────────── App Task Removal Cleanup ───────────────────────

    @Test
    fun `onTaskRemoved cleans up service`() {
        val service = buildService()
        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_START), 0, 1)
        events.clear()

        service.onTaskRemoved(null)

        assertFalse(ContinuedTaskForegroundService.isAssertionHeld)
        assertEquals(listOf("assertionLost"), events)
    }

    @Test
    fun `onTaskRemoved does not record user cancel flag`() {
        val service = buildService()
        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_START), 0, 1)

        service.onTaskRemoved(null)

        assertFalse(stopRequestFlag())
    }

    // ───────────────────────── System Timeout ─────────────────────────

    @Test
    fun `onTimeout notifies listeners and stops service`() {
        val service = buildService()
        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_START), 0, 1)
        events.clear()

        service.onTimeout(1, 0)

        assertEquals(listOf("timeout", "assertionLost"), events)
        assertFalse(ContinuedTaskForegroundService.isAssertionHeld)
    }

    @Test
    fun `single-argument onTimeout behaves identically`() {
        val service = buildService()
        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_START), 0, 1)
        events.clear()

        service.onTimeout(1)

        assertEquals(listOf("timeout", "assertionLost"), events)
    }

    // ───────────────────────── Progress Update ─────────────────────────

    @Test
    fun `UPDATE keeps assertion and refreshes notification`() {
        val service = buildService()
        service.onStartCommand(
            intent(ContinuedTaskForegroundService.ACTION_START)
                .putExtra(ContinuedTaskForegroundService.EXTRA_MAX_PROGRESS, 10),
            0,
            1
        )
        events.clear()

        service.onStartCommand(
            intent(ContinuedTaskForegroundService.ACTION_UPDATE)
                .putExtra(ContinuedTaskForegroundService.EXTRA_PROGRESS, 5)
                .putExtra(ContinuedTaskForegroundService.EXTRA_MAX_PROGRESS, 10),
            0,
            2
        )

        assertTrue(ContinuedTaskForegroundService.isAssertionHeld)
        assertFalse(events.contains("assertionLost"))
    }
}
