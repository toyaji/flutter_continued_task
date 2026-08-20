# flutter_continued_task 생명주기 검증 매트릭스 (Lifecycle Test Matrix)

이 문서는 `flutter_continued_task` 플러그인이 모바일 OS의 다양한 생명주기(Doze 모드, 절전 모드, 백그라운드 전환, 타임아웃, 사용자 중단)에서 정상적으로 동작하는지 검증하기 위한 테스트 시나리오 및 매트릭스를 정의합니다.

---

## 1. 테스트 시나리오 매트릭스

| ID | 시나리오 | 검증 목적 | 플랫폼 | 기대 결과 |
| :--- | :--- | :--- | :--- | :--- |
| **TC-01** | 포그라운드 시작 → 홈/화면끔 | 백그라운드 전환 시 프로세스 및 네트워크 유지 | Android, iOS | • 진행률 알림/잠금화면 UI 유지<br>• Dart 작업이 중단 없이 완주<br>• 완료 후 알림 자동 소멸 |
| **TC-02** | Android Doze 모드 강제 진입 | Doze 모드에서의 FGS 동작 및 네트워크 유지 | Android | • `adb shell dumpsys deviceidle force-idle` 후에도 작업 지속<br>• `UnknownHostException` 없이 전송 유지 |
| **TC-03** | Android 6시간 타임아웃 | `dataSync` FGS 6시간 상한 도달 시 크래시 방지 | Android | • `onTimeout` 발화 시 즉시 서비스 정상 종료<br>• `RemoteServiceException` 크래시 없음<br>• Dart에 `timeout` 이벤트 전달 |
| **TC-04** | 백그라운드 상태에서 `start()` 시도 | 백그라운드 시작 제약 대응 | Android (API 31+), iOS | • 크래시(예외) 없이 `false` 반환<br>• 앱이 대기(Pending) 상태로 안전하게 유지됨 |
| **TC-05** | 알림의 '중단' 버튼 클릭 | 사용자의 능동적 취소 의사 전달 | Android, iOS | • Dart에 `stopRequested` 전달<br>• 작업 큐 안전하게 정지 및 서비스 종료 |
| **TC-06** | 고주파 `update()` 호출 (100회/초) | 채널 직렬화 및 병합(Coalesce) 성능 | 공통 | • UI 멈춤 없이 최신 진행률로 수렴<br>• 마지막 진행률 유실 없음 |
| **TC-07** | 앱 강제 스와이프 킬 후 재시작 | 분리된 서비스 상태 복구 및 정리 | Android | • 재기동 시 `syncState`를 통해 남아있던 서비스 및 중단 요청 복원/정리 |

---

## 2. 실기기 / 시뮬레이터 수동 검증 명령어 가이드

### 2.1 Android 디버깅 및 시뮬레이션
```bash
# 1. 포그라운드 서비스 실행 상태 실시간 확인
adb shell dumpsys activity services | grep -A 10 "dev.flutter.continued_task"

# 2. Doze 모드 강제 진입
adb shell dumpsys deviceidle force-idle

# 3. Doze 모드 해제
adb shell dumpsys deviceidle unforce

# 4. 앱 프로세스 생명주기 및 로그 모니터링
adb logcat -c && adb logcat | grep -iE "ContinuedTask|FlutterContinuedTask"
```

### 2.2 iOS `BGContinuedProcessingTask` 디버깅
1. Xcode에서 앱 실행 및 작업 시작
2. 작업 진행 중 앱을 백그라운드로 전환하고 화면 잠금
3. Xcode LLDB 디버거에서 태스크 만료 강제 시뮬레이션:
```lldb
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"co.zelly.flutter.upload"]
```
4. 콘솔 로그 확인:
```text
[ContinuedTask] 태스크 종료 — 시스템 회수(시간·리소스) / 사용자 중단
```
