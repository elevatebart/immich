import AppIntents

struct RandomPhotoIntent: AppIntent {
  /// How many candidates to pull when an orientation filter has to be applied
  /// client side, since the server can't filter on aspect ratio.
  private static let candidatePoolSize = 60

  static var title: LocalizedStringResource { "Get Random Photo" }
  static var description: IntentDescription {
    IntentDescription(
      "Returns a random photo from your Immich library. Pair it with Set Wallpaper to rotate your background.",
      categoryName: "Photos"
    )
  }

  @Parameter(title: "Album")
  var album: Album?

  @Parameter(title: "Orientation", default: .any)
  var orientation: PhotoOrientation

  @Parameter(title: "Quality", default: .fullsize)
  var quality: PhotoQuality

  static var parameterSummary: some ParameterSummary {
    Summary("Get a random \(\.$orientation) photo from \(\.$album)") {
      \.$quality
    }
  }

  func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
    let api = try await ImmichAPI()

    var filter = (album ?? Album.NONE).filter
    if orientation != .any {
      filter.withExif = true
      filter.size = Self.candidatePoolSize
    }

    let assets = try await api.fetchSearchResults(with: filter)
    guard !assets.isEmpty else {
      throw WidgetError.noAssetsAvailable
    }

    guard let asset = assets.first(where: orientation.matches) else {
      throw WidgetError.noMatchingAssets
    }

    return .result(value: try await api.intentFile(for: asset, quality: quality))
  }
}
