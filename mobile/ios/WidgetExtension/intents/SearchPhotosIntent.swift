import AppIntents

struct SearchPhotosIntent: AppIntent {
  /// Over-fetch factor for the client-side orientation pass, capped so a
  /// portrait filter on a wide library still has something to choose from.
  private static let candidateMultiplier = 4
  private static let candidateCeiling = 250

  static var title: LocalizedStringResource { "Search Photos" }
  static var description: IntentDescription {
    IntentDescription(
      "Searches your Immich library by description, such as \"dog on a beach\". Requires Smart Search on the server.",
      categoryName: "Photos"
    )
  }

  @Parameter(title: "Search", requestValueDialog: "What are you looking for?")
  var query: String

  @Parameter(title: "Album")
  var album: Album?

  /// Each result is held in memory until the intent returns, so a high limit
  /// at Full Size or Original quality can trip the extension's memory ceiling.
  @Parameter(title: "Limit", default: 5, inclusiveRange: (1, 25))
  var limit: Int

  @Parameter(title: "Orientation", default: .any)
  var orientation: PhotoOrientation

  @Parameter(title: "Quality", default: .preview)
  var quality: PhotoQuality

  static var parameterSummary: some ParameterSummary {
    Summary("Search for \(\.$query)") {
      \.$album
      \.$limit
      \.$orientation
      \.$quality
    }
  }

  func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
    let api = try await ImmichAPI()

    let albumIds = (album ?? Album.NONE).filter.albumIds
    var filter = SmartSearchFilter(query: query, albumIds: albumIds)
    filter.isFavorite = album == Album.FAVORITES ? true : nil
    filter.size =
      orientation == .any
      ? limit
      : min(limit * Self.candidateMultiplier, Self.candidateCeiling)

    let assets = try await api.fetchSmartSearchResults(with: filter)
    guard !assets.isEmpty else {
      throw WidgetError.noAssetsAvailable
    }

    let matches = assets.filter(orientation.matches).prefix(limit)
    guard !matches.isEmpty else {
      throw WidgetError.noMatchingAssets
    }

    var files: [IntentFile] = []
    for asset in matches {
      files.append(try await api.intentFile(for: asset, quality: quality))
    }

    return .result(value: files)
  }
}
