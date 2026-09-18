import BackgroundTasks

class BackgroundWorkerApiImpl: BackgroundWorkerFgHostApi {

  func enable() throws {
    BackgroundWorkerApiImpl.scheduleRefreshWorker()
    BackgroundWorkerApiImpl.scheduleProcessingWorker()
    print("BackgroundWorkerApiImpl:enable Background worker scheduled")
  }
  
  func configure(settings: BackgroundWorkerSettings) throws {
    // Android only
  }
  
  func saveNotificationMessage(title: String, body: String) throws {
    // Android only
  }
  
  func disable() throws {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundWorkerApiImpl.refreshTaskID);
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundWorkerApiImpl.processingTaskID);
    print("BackgroundWorkerApiImpl:disableUploadWorker Disabled background workers")
  }
  
  private static let taskIDs = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as! [String]
  private static let refreshTaskID = taskIDs.first { $0.hasSuffix(".refreshUpload") }!
  private static let processingTaskID = taskIDs.first { $0.hasSuffix(".processingUpload") }!
  private static let taskSemaphore = DispatchSemaphore(value: 1)

  /// Runs the upload worker outside the BGTaskScheduler path, for the Shortcuts
  /// intent. Returns nil when a scheduled task already holds the engine, and
  /// otherwise whether the worker finished rather than hitting maxSeconds.
  public static func runOnDemand(maxSeconds: Int) async -> Bool? {
    guard taskSemaphore.wait(timeout: .now()) == .success else {
      return nil
    }

    let resume = ResumeOnce()

    return await withCheckedContinuation { continuation in
      let finish: (Bool) -> Void = { success in
        guard resume.claim() else { return }
        taskSemaphore.signal()
        continuation.resume(returning: success)
      }

      let worker = BackgroundWorker(taskType: .processing, maxSeconds: maxSeconds, completionHandler: finish)

      // Dart can hang without ever calling back, which would strand the
      // semaphore and block every later scheduled backup.
      DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(maxSeconds + 5)) {
        finish(false)
      }

      DispatchQueue.main.async {
        worker.run()
      }
    }
  }

  public static func registerBackgroundWorkers() {
      BGTaskScheduler.shared.register(
          forTaskWithIdentifier: processingTaskID, using: nil) { task in
          if task is BGProcessingTask {
            handleBackgroundProcessing(task: task as! BGProcessingTask)
          }
      }

      BGTaskScheduler.shared.register(
          forTaskWithIdentifier: refreshTaskID, using: nil) { task in
          if task is BGAppRefreshTask {
            handleBackgroundRefresh(task: task as! BGAppRefreshTask)
          }
      }
  }
  
  private static func scheduleRefreshWorker() {
    let backgroundRefresh = BGAppRefreshTaskRequest(identifier: refreshTaskID)
      backgroundRefresh.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 mins

      do {
          try BGTaskScheduler.shared.submit(backgroundRefresh)
      } catch {
          print("Could not schedule the refresh upload task \(error.localizedDescription)")
      }
  }

  private static func scheduleProcessingWorker() {
    let backgroundProcessing = BGProcessingTaskRequest(identifier: processingTaskID)
    
    backgroundProcessing.requiresNetworkConnectivity = true
    backgroundProcessing.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 mins
    
    do {
        try BGTaskScheduler.shared.submit(backgroundProcessing)
    } catch {
        print("Could not schedule the processing upload task \(error.localizedDescription)")
    }
  }
  
  private static func handleBackgroundRefresh(task: BGAppRefreshTask) {
    scheduleRefreshWorker()
    // If another task is running, cede the background time back to the OS
    if taskSemaphore.wait(timeout: .now()) == .success {
      // Restrict the refresh task to run only for a maximum of (maxSeconds) seconds
      runBackgroundWorker(task: task, taskType: .refresh, maxSeconds: 20)
    } else {
      task.setTaskCompleted(success: false)
    }
  }
  
  private static func handleBackgroundProcessing(task: BGProcessingTask) {
    scheduleProcessingWorker()
    taskSemaphore.wait()
    // There are no restrictions for processing tasks. Although, the OS could signal expiration at any time
    runBackgroundWorker(task: task, taskType: .processing, maxSeconds: nil)
  }
  
  /**
   * Executes the background worker within the context of a background task.
   * This method creates a BackgroundWorker, sets up task expiration handling,
   * and manages the synchronization between the background task and the Flutter engine.
   *
   * - Parameters:
   *   - task: The iOS background task that provides the execution context
   *   - taskType: The type of background operation to perform (refresh or processing)
   *   - maxSeconds: Optional timeout for the operation in seconds
   */
  private static func runBackgroundWorker(task: BGTask, taskType: BackgroundTaskType, maxSeconds: Int?) {
    defer { taskSemaphore.signal() }
    let semaphore = DispatchSemaphore(value: 0)
    var isSuccess = true
    
    let backgroundWorker = BackgroundWorker(taskType: taskType, maxSeconds: maxSeconds) { success in
      isSuccess = success
      semaphore.signal()
    }

    task.expirationHandler = {
      DispatchQueue.main.async {
        backgroundWorker.close()
      }
      isSuccess = false
      
      // Schedule a timer to signal the semaphore after 2 seconds
      Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
        semaphore.signal()
      }
    }

    DispatchQueue.main.async {
      backgroundWorker.run()
    }

    semaphore.wait()
    task.setTaskCompleted(success: isSuccess)
    print("Background task completed with success: \(isSuccess)")
  }
}

/// One-shot latch so a worker callback and its watchdog can't both resume.
private final class ResumeOnce {
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }

    if claimed {
      return false
    }

    claimed = true
    return true
  }
}
