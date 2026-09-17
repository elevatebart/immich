import AppIntents
import UniformTypeIdentifiers

// MARK: Errors

// Shortcuts surfaces the message from this protocol, not from LocalizedError.
extension WidgetError: CustomLocalizedStringResourceConvertible {
  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .noLogin: return "Log in to Immich on this device first"
    case .fetchFailed: return "Unable to connect to Immich"
    case .albumNotFound: return "Album not found"
    case .noAssetsAvailable: return "No photos available"
    case .noMatchingAssets: return "No photos matched the selected filters"
    }
  }
}

extension FetchError: CustomLocalizedStringResourceConvertible {
  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .invalidURL: return "Invalid Immich server URL"
    case .invalidImage, .unableToResize: return "Unable to read the photo"
    case .fetchFailed: return "Unable to download the photo from Immich"
    }
  }
}

// MARK: Parameter Types

enum PhotoOrientation: String, AppEnum {
  case any
  case portrait
  case landscape

  static var typeDisplayRepresentation = TypeDisplayRepresentation(
    name: "Orientation"
  )

  static var caseDisplayRepresentations: [PhotoOrientation: DisplayRepresentation] = [
    .any: "Any",
    .portrait: "Portrait",
    .landscape: "Landscape",
  ]

  /// Assets without EXIF dimensions can't be classified, so they only pass
  /// when no orientation was requested.
  func matches(_ asset: Asset) -> Bool {
    if self == .any {
      return true
    }

    guard let size = asset.displaySize else {
      return false
    }

    return self == .portrait ? size.height > size.width : size.width > size.height
  }
}

enum PhotoQuality: String, AppEnum {
  case preview
  case fullsize
  case original

  static var typeDisplayRepresentation = TypeDisplayRepresentation(
    name: "Quality"
  )

  static var caseDisplayRepresentations: [PhotoQuality: DisplayRepresentation] = [
    .preview: "Preview (faster)",
    .fullsize: "Full Size",
    .original: "Original File",
  ]

  var imageSize: ImageSize {
    switch self {
    case .preview: return .preview
    case .fullsize: return .fullsize
    case .original: return .original
    }
  }
}

// MARK: Intent

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

    let (data, mimeType) = try await api.fetchImageData(
      asset: asset,
      size: quality.imageSize
    )

    let type = UTType(mimeType: mimeType) ?? .jpeg
    let file = IntentFile(
      data: data,
      filename: "\(asset.id).\(type.preferredFilenameExtension ?? "jpg")",
      type: type
    )

    return .result(value: file)
  }
}

// MARK: Siri & Spotlight

struct ImmichAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: RandomPhotoIntent(),
      phrases: [
        "Get a random photo from \(.applicationName)",
        "Random \(.applicationName) photo",
      ],
      shortTitle: "Random Photo",
      systemImageName: "photo.on.rectangle.angled"
    )
  }
}
