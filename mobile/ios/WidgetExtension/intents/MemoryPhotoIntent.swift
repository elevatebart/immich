import AppIntents

struct MemoryPhotoIntent: AppIntent {
  static var title: LocalizedStringResource { "Get Memory Photo" }
  static var description: IntentDescription {
    IntentDescription(
      "Returns a photo from today's memories, the same set the app shows as On This Day.",
      categoryName: "Photos"
    )
  }

  @Parameter(title: "Orientation", default: .any)
  var orientation: PhotoOrientation

  @Parameter(title: "Quality", default: .fullsize)
  var quality: PhotoQuality

  static var parameterSummary: some ParameterSummary {
    Summary("Get a \(\.$orientation) photo from today's memories") {
      \.$quality
    }
  }

  func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
    let api = try await ImmichAPI()

    let memories = try await api.fetchMemory(for: Date())
    let photos = memories.flatMap(\.assets).filter { $0.type == .image }
    guard !photos.isEmpty else {
      throw WidgetError.noAssetsAvailable
    }

    // Memories arrive in a stable order, so pick rather than take the first.
    guard let asset = photos.filter(orientation.matches).randomElement() else {
      throw WidgetError.noMatchingAssets
    }

    return .result(value: try await api.intentFile(for: asset, quality: quality))
  }
}
