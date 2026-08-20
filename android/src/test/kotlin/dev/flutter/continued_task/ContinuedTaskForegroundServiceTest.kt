package dev.flutter.continued_task

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
 * 서비스의 분기 로직을 JVM에서 검증한다.
 *
 * **여기서 잡히는 것과 못 잡는 것을 구분해 둔다.** 존재하지 않는 네이티브 API나
 * 타입 오류는 테스트가 아니라 **컴파일**이 잡는다(example 앱 빌드가 그 역할).
 * 이 테스트가 잡는 것은 "어떤 인텐트가 왔을 때 어떤 상태·이벤트가 되는가"라는
 * 분기 로직이다.
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

    // ─────────────────────────── 수명 확보 ───────────────────────────

    /**
     * 확보 시점은 **`startForeground`가 실제로 성공한 뒤**여야 한다.
     * 시작 요청이 받아들여진 것과 수명이 확보된 것은 다르다 — 이 구분이 없으면
     * Dart 쪽 실패 분류가 "확보 있음"으로 오판해 대기여야 할 실패를 실패로 쓴다.
     */
    @Test
    fun `START는 확보를 잡고 알린다`() {
        val service = buildService()

        service.onStartCommand(
            intent(ContinuedTaskForegroundService.ACTION_START)
                .putExtra(ContinuedTaskForegroundService.EXTRA_TITLE, "테스트")
                .putExtra(ContinuedTaskForegroundService.EXTRA_MAX_PROGRESS, 10),
            0,
            1
        )

        assertTrue(ContinuedTaskForegroundService.isAssertionHeld)
        assertEquals(listOf("assertionAcquired"), events)
    }

    @Test
    fun `STOP은 확보를 놓고 알린다`() {
        val service = buildService()
        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_START), 0, 1)
        events.clear()

        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_STOP), 0, 2)

        assertFalse(ContinuedTaskForegroundService.isAssertionHeld)
        assertEquals(listOf("assertionLost"), events)
    }

    /** 알 수 없는 인텐트로 서비스가 살아남으면 알림만 남고 아무도 못 내린다. */
    @Test
    fun `알 수 없는 액션은 서비스를 내린다`() {
        val service = buildService()

        service.onStartCommand(intent("dev.flutter.continued_task.UNKNOWN"), 0, 1)

        assertFalse(ContinuedTaskForegroundService.isAssertionHeld)
        assertTrue(events.contains("assertionLost"))
    }

    @Test
    fun `프로세스가 죽으면 서비스를 되살리지 않는다`() {
        val service = buildService()

        val result = service.onStartCommand(
            intent(ContinuedTaskForegroundService.ACTION_START), 0, 1
        )

        // Dart 큐가 함께 사라지므로 서비스만 부활하면 올릴 대상 없는 알림만 남는다.
        assertEquals(android.app.Service.START_NOT_STICKY, result)
    }

    // ─────────────────────── 사용자 중단 전달 ───────────────────────

    @Test
    fun `Dart가 붙어 있으면 중단을 곧바로 전달한다`() {
        val service = buildService()

        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_USER_CANCEL), 0, 1)

        assertEquals(listOf("stopRequested"), events)
        // 전달됐으므로 다음 기동에 다시 처리할 이유가 없다.
        assertFalse(stopRequestFlag())
    }

    /**
     * **이 서비스의 존재 이유가 바로 이 구간이다.** Activity가 파기된 뒤에도
     * 프로세스를 살려두는 것이 목적인데, 그때 눌린 중단을 흘려보내면 알림이
     * `setOngoing(true)`라 사용자가 지울 수도 없는 채로 남는다.
     */
    @Test
    fun `Dart가 없으면 중단 의사를 남기고 서비스를 내린다`() {
        ContinuedTaskForegroundService.eventListener = null
        val service = buildService()

        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_USER_CANCEL), 0, 1)

        assertTrue(stopRequestFlag())
        assertFalse(ContinuedTaskForegroundService.isAssertionHeld)
    }

    // ─────────────────────── 앱 강제 종료 정리 ───────────────────────

    @Test
    fun `최근 앱에서 밀어내면 서비스를 정리한다`() {
        val service = buildService()
        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_START), 0, 1)
        events.clear()

        service.onTaskRemoved(null)

        assertFalse(ContinuedTaskForegroundService.isAssertionHeld)
        assertEquals(listOf("assertionLost"), events)
    }

    /** 정리는 사용자 중단이 아니다 — 중단 의사로 기록되면 다음 실행이 멈춘다. */
    @Test
    fun `밀어내기는 중단 의사로 기록하지 않는다`() {
        val service = buildService()
        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_START), 0, 1)

        service.onTaskRemoved(null)

        assertFalse(stopRequestFlag())
    }

    // ───────────────────────── 시스템 회수 ─────────────────────────

    /**
     * Android 15+ `dataSync`의 24시간당 6시간 상한.
     * **여기서 정지하지 않으면 `RemoteServiceException`으로 앱이 강제 종료된다.**
     */
    @Test
    fun `시간 초과는 알리고 서비스를 내린다`() {
        val service = buildService()
        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_START), 0, 1)
        events.clear()

        service.onTimeout(1, 0)

        assertEquals(listOf("timeout", "assertionLost"), events)
        assertFalse(ContinuedTaskForegroundService.isAssertionHeld)
    }

    /** API 34의 단일 인자 형태도 같은 처리를 해야 한다. */
    @Test
    fun `단일 인자 시간 초과도 같은 처리를 한다`() {
        val service = buildService()
        service.onStartCommand(intent(ContinuedTaskForegroundService.ACTION_START), 0, 1)
        events.clear()

        service.onTimeout(1)

        assertEquals(listOf("timeout", "assertionLost"), events)
    }

    // ───────────────────────── 진행률 갱신 ─────────────────────────

    @Test
    fun `UPDATE는 확보를 유지한 채 갱신만 한다`() {
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
        // 이미 확보 중이어도 갱신 경로가 확보를 재확인해 알리는 것은 무해하다.
        assertFalse(events.contains("assertionLost"))
    }
}
