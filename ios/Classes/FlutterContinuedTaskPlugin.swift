import BackgroundTasks
import Flutter
import UIKit

/// iOS 26의 `BGContinuedProcessingTask`로 백그라운드 수명을 확보한다.
///
/// 앱이 강제 종료되면 태스크는 시스템이 실패로 확정하며, 그 배너는 앱이
/// 제거할 수 없다. 이를 없애려는 방어 코드를 추가하지 마라 — 닿지 않는다.
/// 근거: `docs/design/upload/steps/L1-test-matrix.md`
public class FlutterContinuedTaskPlugin: NSObject, FlutterPlugin {

  public static let channelName = "dev.flutter.continued_task/channel"

  private var channel: FlutterMethodChannel?
  private var activeTask: NSObject?
  private var taskIdentifier: String = "co.zelly.flutter.upload"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = FlutterContinuedTaskPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)

    instance.registerTaskHandler()
  }

  /// 이전 실행이 남긴 대기 요청이 뒤늦게 전달되는 경우를 가른다.
  private var startRequestedInThisSession = false

  private func registerTaskHandler() {
    guard #available(iOS 26.0, *) else { return }

    // 이 등록은 앱 기동이 끝나기 전에 이뤄져야 한다.
    if let permittedIds = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] {
      for id in permittedIds {
        BGTaskScheduler.shared.register(
          forTaskWithIdentifier: id,
          using: DispatchQueue.main
        ) { [weak self] task in
          guard let continued = task as? BGContinuedProcessingTask else {
            task.setTaskCompleted(success: false)
            return
          }
          guard let self = self else {
            continued.setTaskCompleted(success: true)
            return
          }
          if !self.startRequestedInThisSession {
            NSLog("[FlutterContinuedTask] 요청하지 않은 태스크 — 즉시 종료한다")
            continued.setTaskCompleted(success: true)
            return
          }
          self.attach(continued)
        }
      }
    }
  }

  @available(iOS 26.0, *)
  private func attach(_ task: BGContinuedProcessingTask) {
    setActive(task)

    task.expirationHandler = { [weak self] in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.finishExpired(task)
      }
    }
  }

  /// 만료 사유(사용자 중단 / 시스템 회수)를 API가 구분해 주지 않는다.
  /// 사용자 중단으로 간주한다 — 반대로 오해하면 끈 작업이 되살아난다.
  @available(iOS 26.0, *)
  private func finishExpired(_ task: BGContinuedProcessingTask) {
    setActive(nil)
    notify("stopRequested")
    task.setTaskCompleted(success: true)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "start":
      result(start(args: args))
    case "update":
      update(args: args)
      result(true)
    case "stop":
      stop()
      result(nil)
    case "syncState":
      result([
        "assertionHeld": activeTask != nil,
        "stopRequested": false
      ])
    case "ackStopRequest":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(args: [String: Any]?) -> Bool {
    guard #available(iOS 26.0, *) else { return false }

    let customTaskId = args?["iosTaskIdentifier"] as? String
    if let customTaskId = customTaskId, !customTaskId.isEmpty {
      self.taskIdentifier = customTaskId
    }

    if activeTask != nil {
      update(args: args)
      return true
    }

    guard UIApplication.shared.applicationState == .active else {
      NSLog("[FlutterContinuedTask] 제출 불가 — 앱이 포그라운드가 아닙니다")
      return false
    }

    // 이 시점 이후 핸들러로 들어오는 태스크는 우리가 요청한 것이다.
    startRequestedInThisSession = true

    let title = args?["title"] as? String ?? "작업 진행 중"
    let subtitle = args?["subtitle"] as? String ?? ""

    let request = BGContinuedProcessingTaskRequest(
      identifier: self.taskIdentifier,
      title: title,
      subtitle: subtitle
    )

    do {
      try BGTaskScheduler.shared.submit(request)
      NSLog("[FlutterContinuedTask] 태스크 제출 성공: %@", self.taskIdentifier)
      return true
    } catch {
      NSLog("[FlutterContinuedTask] 태스크 제출 거부: %@", error.localizedDescription)
      return false
    }
  }

  private func update(args: [String: Any]?) {
    guard #available(iOS 26.0, *),
          let task = activeTask as? BGContinuedProcessingTask else { return }

    let progress = args?["progress"] as? Int ?? 0
    let maxProgress = args?["maxProgress"] as? Int ?? 100
    let title = args?["title"] as? String
    let subtitle = args?["subtitle"] as? String

    task.progress.totalUnitCount = Int64(max(maxProgress, 1))
    task.progress.completedUnitCount = Int64(progress)

    if let title = title {
      task.updateTitle(title, subtitle: subtitle ?? "")
    } else if let subtitle = subtitle {
      task.updateTitle(task.title, subtitle: subtitle)
    }
  }

  private func stop() {
    startRequestedInThisSession = false
    guard #available(iOS 26.0, *) else { return }

    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: self.taskIdentifier)

    guard let task = activeTask as? BGContinuedProcessingTask else { return }
    setActive(nil)
    task.setTaskCompleted(success: true)
  }

  private func setActive(_ task: NSObject?) {
    activeTask = task
    notify(task == nil ? "assertionLost" : "assertionAcquired")
  }

  private func notify(_ method: String) {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod(method, arguments: nil)
    }
  }
}
