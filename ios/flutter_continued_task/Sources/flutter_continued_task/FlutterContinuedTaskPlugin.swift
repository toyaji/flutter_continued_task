import BackgroundTasks
import Flutter
import UIKit

/// Holds background process lifecycle on iOS 26 using `BGContinuedProcessingTask`.
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

  /// Distinguishes late pending requests from previous app launches.
  private var startRequestedInThisSession = false

  private func registerTaskHandler() {
    guard #available(iOS 26.0, *) else { return }

    // Must be registered before app launch completes.
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
            NSLog("[FlutterContinuedTask] Unrequested task - completing immediately")
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

  /// Expiration reasons (user cancellation vs system reclamation) are not distinguished by the API.
  /// We treat it as stop requested to avoid reviving stopped work.
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
      NSLog("[FlutterContinuedTask] Cannot submit - app is not in foreground")
      return false
    }

    // Tasks entering handler after this point are requested by this session.
    startRequestedInThisSession = true

    let title = args?["title"] as? String ?? "Task in progress"
    let subtitle = args?["subtitle"] as? String ?? ""

    let request = BGContinuedProcessingTaskRequest(
      identifier: self.taskIdentifier,
      title: title,
      subtitle: subtitle
    )

    do {
      try BGTaskScheduler.shared.submit(request)
      NSLog("[FlutterContinuedTask] Task submitted successfully: %@", self.taskIdentifier)
      return true
    } catch {
      NSLog("[FlutterContinuedTask] Task submission rejected: %@", error.localizedDescription)
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
