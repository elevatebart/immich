import AppIntents

/// Runs the same worker as the scheduled background upload, but at a moment the
/// user picks rather than whenever BGTaskScheduler feels like it. The Dart side
/// hands the files to URLSession, so uploading continues once this returns and
/// survives the phone staying locked.
@available(iOS 16.0, *)
struct BackupLibraryIntent: AppIntent {
  /// Long enough for the worker to sync and queue the uploads, short enough
  /// that Shortcuts doesn't kill the intent first. Apple doesn't document the
  /// ceiling, so this is a conservative guess.
  private static let budgetSeconds = 25

  static var title: LocalizedStringResource { "Back Up My Library" }
  static var description: IntentDescription {
    IntentDescription(
      "Queues everything still waiting to back up. Uploads carry on in the background, so the phone can stay locked.",
      categoryName: "Backup"
    )
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let didFinish = await BackgroundWorkerApiImpl.runOnDemand(maxSeconds: Self.budgetSeconds)
    else {
      return .result(dialog: "A backup is already running")
    }

    return .result(
      dialog: didFinish ? "Backup queued" : "Backup started, but ran out of time to queue everything"
    )
  }
}
