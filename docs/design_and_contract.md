# flutter_continued_task 설계 문서 및 플랫폼 인터페이스 계약

## 1. 개요 (Overview)

`flutter_continued_task`는 사용자가 포그라운드에서 시작한 장시간 작업(대용량 파일 업로드, 로컬 데이터베이스 백업, 온디바이스 AI 모델 추론, 동영상 인코딩/내보내기 등)이 **앱이 백그라운드로 전환되더라도 OS에 의해 프로세스가 중단(Suspend)되거나 네트워크가 차단되지 않도록 프로세스 수명을 확보(Assertion)하고, 시스템 진행률 알림 UI를 동기화하는 범용 플러그인**입니다.

---

## 2. 플랫폼별 핵심 메커니즘 (Platform Implementations)

### 2.1 Android: `ForegroundService` (`dataSync`)
- **수명 유지 방식**: API 26+ `startForegroundService` / API 34+ `FOREGROUND_SERVICE_DATA_SYNC` 타입을 갖는 포그라운드 서비스 기동.
- **알림 UI (Notification)**:
  - 진행률 바(`setProgress`), 고정 알림(`setOngoing(true)`), 알림 탭 시 메인 액티비티 복귀.
  - 선택적 취소 액션("중단") 버튼 지원.
- **상한 타임아웃 방어**:
  - Android 15+ `dataSync`의 24시간당 6시간 상한 도달 시 `onTimeout` 콜백을 수신하여 `RemoteServiceException` 크래시 없이 안전하게 서비스를 종료하고 Dart 계층에 `timeout` 이벤트를 통지.
- **안전한 시작**:
  - Android 12+ 백그라운드 시작 금지(`ForegroundServiceStartNotAllowedException`) 발생 시 예외를 던지지 않고 `false`를 반환하여 호출부가 대기(Pending) 상태로 안전하게 전환되도록 보장.

### 2.2 iOS: `BGContinuedProcessingTask` (iOS 26.0+)
- **수명 유지 방식**: 사용자가 포그라운드에서 트리거한 작업에 대해 `BGContinuedProcessingTaskRequest`를 제출(`submit`)하여 백그라운드에서도 메인 Dart Isolate 및 네트워크 전송을 유지.
- **진행률 및 잠금화면 UI**:
  - `task.progress` 및 `task.updateTitle(_:subtitle:)`를 통해 잠금화면/다이내믹 아일랜드에 실시간 진행률 노출.
- **중단 및 시스템 회수 구분**:
  - `expirationHandler` 발화 시 `task.progress.isCancelled`를 검사하여 **사용자의 능동적 중단(`stopRequested`)**과 **시스템의 리소스/시간 회수(`timeout`)**를 엄격히 분리 통지.
- **폴백 (iOS 17~25)**:
  - `BGContinuedProcessingTask` 미지원 기기에서는 불완전한 `beginBackgroundTask`를 무리하게 사용하지 않고 `false`를 반환하여 앱 레벨의 대기(Pending) 정책으로 폴백.

---

## 3. 플랫폼 인터페이스 계약 (Platform Interface Contract)

### 3.1 MethodChannel 규격
- **Channel Name**: `dev.flutter.continued_task/channel`

#### Dart → Native (Methods)
| 메서드명 | 인자 (Arguments) | 반환값 (Return) | 설명 |
| :--- | :--- | :--- | :--- |
| `start` | `taskId: String`<br>`title: String`<br>`subtitle: String?`<br>`initialProgress: Int`<br>`maxProgress: Int`<br>`indeterminate: Boolean`<br>`allowCancel: Boolean`<br>`cancelActionLabel: String?`<br>`notificationIcon: String?`<br>`channelId: String?`<br>`channelName: String?`<br>`iosTaskIdentifier: String?` | `Boolean` | 태스크 수명 확보 시작 요청. 성공 시 `true`, 시작 불가(백그라운드 제약 등) 시 `false` |
| `update` | `taskId: String`<br>`progress: Int`<br>`maxProgress: Int?`<br>`title: String?`<br>`subtitle: String?` | `Boolean` | 진행률 및 텍스트 갱신 |
| `stop` | `taskId: String` | `void` | 태스크 종료 및 네이티브 수명 해제 |
| `syncState` | 없음 | `Map<String, dynamic>`<br>`{ assertionHeld: Boolean, stopRequested: Boolean }` | 앱 재진입 시 네이티브에 남은 현재 상태 동기화 조회 |
| `ackStopRequest` | 없음 | `void` | Dart가 중단 요청 처리를 완료했음을 네이티브에 알림 (플래그 리셋) |

#### Native → Dart (Events / Reverse Calls)
| 이벤트명 | 인자 | 설명 |
| :--- | :--- | :--- |
| `assertionAcquired` | `null` | 네이티브 컴포넌트(FGS/ContinuedTask)가 실제로 수명을 확보함 |
| `assertionLost` | `null` | 네이티브 컴포넌트가 종료되어 수명 확보가 해제됨 |
| `stopRequested` | `null` | 사용자가 시스템 알림/잠금화면에서 '중단'을 탭함 |
| `timeout` | `null` | OS 리소스 제약이나 6시간 상한 도달로 태스크가 강제 회수됨 |

---

## 4. 고주파 갱신 직렬화 및 스로틀 (Coalescing & Throttling)

대량의 파일 전송, 루프 기반 AI 추론, 대규모 DB 덤프 등은 밀리초 단위로 수십 번 진행률 갱신(`update`)을 호출할 수 있습니다.
`flutter_continued_task`의 Dart 계층은 자체 **비동기 큐 직렬화 및 최신 값 병합(Coalescing)**을 수행하여:
1. 네이티브 MethodChannel의 직렬화 오버헤드를 최소화하고,
2. UI 렌더링 스레드의 프레임 드랍을 방지하며,
3. 최종 진행률(`progress == maxProgress`)은 반드시 유실 없이 전달되도록 보장합니다.
