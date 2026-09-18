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

  @Parameter(title: "Person")
  var person: Person?

  @Parameter(title: "Favorites Only", default: false)
  var favoritesOnly: Bool

  @Parameter(title: "Taken After")
  var takenAfter: Date?

  @Parameter(title: "Taken Before")
  var takenBefore: Date?

  @Parameter(title: "Rating", default: .any)
  var rating: PhotoRating

  @Parameter(title: "Orientation", default: .any)
  var orientation: PhotoOrientation

  @Parameter(title: "Quality", default: .fullsize)
  var quality: PhotoQuality

  static var parameterSummary: some ParameterSummary {
    Summary("Get a random photo from \(\.$album)") {
      \.$person
      \.$favoritesOnly
      \.$takenAfter
      \.$takenBefore
      \.$rating
      \.$orientation
      \.$quality
    }
  }

  func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
    let api = try await ImmichAPI()

    var filter = (album ?? Album.NONE).filter
    if let person {
      filter.personIds = [person.id]
    }
    if favoritesOnly {
      filter.isFavorite = true
    }
    filter.takenAfter = takenAfter
    filter.takenBefore = takenBefore
    filter.rating = rating.value

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
