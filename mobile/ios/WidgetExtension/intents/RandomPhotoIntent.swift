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

  @Parameter(title: "Mode", default: .simple)
  var mode: FilterMode

  @Parameter(title: "Album")
  var album: Album?

  @Parameter(title: "Person")
  var person: Person?

  @Parameter(title: "Any Of These People")
  var people: [Person]?

  @Parameter(title: "But Not These People")
  var excludedPeople: [Person]?

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
    When(\.$mode, .equalTo, FilterMode.advanced) {
      Summary("Get a random photo") {
        \.$mode
        \.$album
        \.$people
        \.$excludedPeople
        \.$favoritesOnly
        \.$takenAfter
        \.$takenBefore
        \.$rating
        \.$orientation
        \.$quality
      }
    } otherwise: {
      Summary("Get a random photo") {
        \.$mode
        \.$album
        \.$person
        \.$favoritesOnly
        \.$takenAfter
        \.$takenBefore
        \.$rating
        \.$orientation
        \.$quality
      }
    }
  }

  func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
    let api = try await ImmichAPI()
    let poolSize = orientation == .any ? 1 : Self.candidatePoolSize
    let needsExif = orientation != .any

    let assets =
      mode == .advanced
      ? try await api.fetchSearchResults(
        structured: structuredRequest(size: poolSize, withExif: needsExif)
      )
      : try await api.fetchSearchResults(
        with: flatFilter(size: poolSize, withExif: needsExif)
      )

    guard !assets.isEmpty else {
      throw WidgetError.noAssetsAvailable
    }

    guard let asset = assets.first(where: orientation.matches) else {
      throw WidgetError.noMatchingAssets
    }

    return .result(value: try await api.intentFile(for: asset, quality: quality))
  }

  /// Deprecated flat fields, which every server version understands.
  private func flatFilter(size: Int, withExif: Bool) -> SearchFilter {
    var filter = (album ?? Album.NONE).filter
    filter.size = size
    filter.withExif = withExif

    if let person {
      filter.personIds = [person.id]
    }
    if favoritesOnly {
      filter.isFavorite = true
    }
    filter.takenAfter = takenAfter
    filter.takenBefore = takenBefore
    filter.rating = rating.value

    return filter
  }

  /// Structured shape, the only one that can express "none of these people".
  private func structuredRequest(size: Int, withExif: Bool) -> StructuredSearchRequest {
    var filter = StructuredFilter(type: EnumFilterAssetType(eq: .image))

    if let album, !album.isVirtual {
      filter.albumIds = IdsFilter(any: [album.id])
    }

    let included = (people ?? []).map(\.id)
    let excluded = (excludedPeople ?? []).map(\.id)
    if !included.isEmpty || !excluded.isEmpty {
      filter.personIds = IdsFilter(
        any: included.isEmpty ? nil : included,
        none: excluded.isEmpty ? nil : excluded
      )
    }

    if favoritesOnly || album == Album.FAVORITES {
      filter.isFavorite = BoolFilter(eq: true)
    }
    if takenAfter != nil || takenBefore != nil {
      filter.takenAt = DateFilter(gte: takenAfter, lte: takenBefore)
    }
    if let value = rating.value {
      filter.rating = NumberFilter(eq: value)
    }

    return StructuredSearchRequest(size: size, withExif: withExif, filter: filter)
  }
}
