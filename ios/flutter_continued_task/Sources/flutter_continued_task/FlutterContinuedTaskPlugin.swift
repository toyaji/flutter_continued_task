import BackgroundTasks
import Flutter
import UIKit
import UserNotifications

/// Holds background process lifecycle on iOS 26 using `BGContinuedProcessingTask`.
public class FlutterContinuedTaskPlugin: NSObject, FlutterPlugin {

  public static let channelName = "io.github.toyaji.continued_task/channel"

  private var channel: FlutterMethodChannel?

  /// Running tasks, keyed by the BGTaskScheduler identifier they were submitted
  /// with. A single slot used to be enough — a second submission finished the
  /// first one, so two tasks could never coexist.
  private static var activeTasks: [String: NSObject] = [:]

  /// taskId (Dart) -> BGTaskScheduler identifier, and back.
  private static var identifierByTaskId: [String: String] = [:]
  private static var taskIdByIdentifier: [String: String] = [:]

  /// Identifiers declared in `BGTaskSchedulerPermittedIdentifiers`, in order.
  /// The first one keeps serving single-task apps exactly as before.
  private static var permittedIdentifiers: [String] = []

  /// Registration happens once per process.
  ///
  /// `BGTaskScheduler` documents that "the system kills the app on the second
  /// registration of the same task identifier", and this plugin registers from
  /// `register(with:)` — which runs again for every additional FlutterEngine.
  private static var didRegisterHandlers = false

  /// The plugin instance that owns the channel used for native -> Dart events.
  private static weak var eventDelegate: FlutterContinuedTaskPlugin?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = FlutterContinuedTaskPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventDelegate = instance

    instance.registerTaskHandler()
  }

  /// Distinguishes late pending requests from previous app launches.
  private var startRequestedInThisSession = false

  private func registerTaskHandler() {
    guard #available(iOS 26.0, *) else { return }
    guard !Self.didRegisterHandlers else { return }
    Self.didRegisterHandlers = true

    // Must be registered before app launch completes.
    if let permittedIds = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] {
      Self.permittedIdentifiers = permittedIds
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
            continued.setTaskCompleted(success: false)
            return
          }
          if !self.startRequestedInThisSession {
            NSLog("[FlutterContinuedTask] Unrequested task from previous session - discarding")
            continued.setTaskCompleted(success: false)
            return
          }
          self.attach(continued)
        }
      }
    }
  }

  @available(iOS 26.0, *)
  private func attach(_ task: BGContinuedProcessingTask) {
    // Replace only the task holding this identifier — other identifiers keep
    // running. Finishing "whatever was active" is what stopped two tasks from
    // ever coexisting.
    if let existing = Self.activeTasks[task.identifier] as? BGContinuedProcessingTask,
       existing !== task {
      existing.setTaskCompleted(success: false)
    }

    setActive(task, for: task.identifier)

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
    let identifier = task.identifier
    setActive(nil, for: identifier)
    notify("stopRequested", identifier: identifier)
    task.setTaskCompleted(success: false)
  }

  /// The scheduler identifier serving [taskId], assigning a free one on first use.
  private func identifier(for taskId: String, requested: String?) -> String? {
    if let requested = requested, !requested.isEmpty {
      // An explicit identifier keeps 0.1.x behaviour, including apps that set
      // one per task themselves.
      Self.identifierByTaskId[taskId] = requested
      Self.taskIdByIdentifier[requested] = taskId
      return requested
    }
    if let existing = Self.identifierByTaskId[taskId] { return existing }

    let taken = Set(Self.identifierByTaskId.values)
    // Slot order follows Info.plist, so a single-task app always lands on the
    // first identifier — the one it has been using all along.
    guard let free = Self.permittedIdentifiers.first(where: { !taken.contains($0) })
    else {
      NSLog("[FlutterContinuedTask] No free identifier for task %@ — declare more in BGTaskSchedulerPermittedIdentifiers", taskId)
      return nil
    }
    Self.identifierByTaskId[taskId] = free
    Self.taskIdByIdentifier[free] = taskId
    return free
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
      stop(args: args)
      result(nil)
    case "requestNotificationPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        DispatchQueue.main.async {
          result(granted)
        }
      }
    case "syncState":
      let taskId = args?["taskId"] as? String
      let held: Bool
      if let taskId = taskId, let identifier = Self.identifierByTaskId[taskId] {
        held = Self.activeTasks[identifier] != nil
      } else {
        held = !Self.activeTasks.isEmpty
      }
      result([
        "assertionHeld": held,
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

    let taskId = args?["taskId"] as? String ?? "default_task"
    guard let identifier = identifier(
      for: taskId,
      requested: args?["iosTaskIdentifier"] as? String
    ) else { return false }

    // Already running under this identifier: refresh its metadata only.
    if Self.activeTasks[identifier] is BGContinuedProcessingTask {
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
      identifier: identifier,
      title: title,
      subtitle: subtitle
    )

    do {
      try BGTaskScheduler.shared.submit(request)
      NSLog("[FlutterContinuedTask] Task submitted successfully: %@", identifier)
      return true
    } catch {
      NSLog("[FlutterContinuedTask] Task submission rejected: %@", error.localizedDescription)
      if Self.activeTasks.isEmpty { startRequestedInThisSession = false }
      return false
    }
  }

  private func update(args: [String: Any]?) {
    guard #available(iOS 26.0, *) else { return }
    let taskId = args?["taskId"] as? String ?? "default_task"
    guard let identifier = Self.identifierByTaskId[taskId],
          let task = Self.activeTasks[identifier] as? BGContinuedProcessingTask
    else { return }

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

  private func stop(args: [String: Any]?) {
    guard #available(iOS 26.0, *) else { return }

    let taskId = args?["taskId"] as? String ?? "default_task"
    let success = args?["success"] as? Bool ?? true
    guard let identifier = Self.identifierByTaskId[taskId] else { return }

    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)

    let task = Self.activeTasks[identifier] as? BGContinuedProcessingTask
    setActive(nil, for: identifier)
    Self.identifierByTaskId.removeValue(forKey: taskId)
    Self.taskIdByIdentifier.removeValue(forKey: identifier)
    // Only the last task leaving clears the session flag — clearing it while
    // another task runs would make its handler discard the task as stale.
    if Self.activeTasks.isEmpty { startRequestedInThisSession = false }
    task?.setTaskCompleted(success: success)
  }

  private func setActive(_ task: NSObject?, for identifier: String) {
    if let task = task {
      Self.activeTasks[identifier] = task
    } else {
      Self.activeTasks.removeValue(forKey: identifier)
    }
    notify(task == nil ? "assertionLost" : "assertionAcquired", identifier: identifier)
  }

  private func notify(_ method: String, identifier: String) {
    // Dart routes by task id, so every event carries the task it belongs to.
    let taskId = Self.taskIdByIdentifier[identifier] ?? "default_task"
    DispatchQueue.main.async {
      let target = Self.eventDelegate ?? self
      target.channel?.invokeMethod(method, arguments: ["taskId": taskId])
    }
  }
}
