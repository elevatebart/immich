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

  /// Assets without known dimensions can't be classified, so they only pass
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

enum PhotoRating: String, AppEnum {
  case any
  case one
  case two
  case three
  case four
  case five

  static var typeDisplayRepresentation = TypeDisplayRepresentation(
    name: "Rating"
  )

  static var caseDisplayRepresentations: [PhotoRating: DisplayRepresentation] = [
    .any: "Any",
    .one: "★",
    .two: "★★",
    .three: "★★★",
    .four: "★★★★",
    .five: "★★★★★",
  ]

  /// nil leaves the field off the request entirely, which the server reads as
  /// "don't filter" rather than "unrated".
  var value: Int? {
    switch self {
    case .any: return nil
    case .one: return 1
    case .two: return 2
    case .three: return 3
    case .four: return 4
    case .five: return 5
    }
  }
}

// MARK: Shared Helpers

extension ImmichAPI {
  func intentFile(for asset: Asset, quality: PhotoQuality) async throws -> IntentFile {
    let (data, mimeType) = try await fetchImageData(asset: asset, size: quality.imageSize)
    let type = UTType(mimeType: mimeType) ?? .jpeg

    return IntentFile(
      data: data,
      filename: "\(asset.id).\(type.preferredFilenameExtension ?? "jpg")",
      type: type
    )
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
    AppShortcut(
      intent: MemoryPhotoIntent(),
      phrases: [
        "Get a memory from \(.applicationName)",
        "\(.applicationName) memories",
      ],
      shortTitle: "Memory Photo",
      systemImageName: "sparkles.rectangle.stack"
    )
    AppShortcut(
      intent: SearchPhotosIntent(),
      phrases: [
        "Search \(.applicationName)",
        "Search photos in \(.applicationName)",
      ],
      shortTitle: "Search Photos",
      systemImageName: "magnifyingglass"
    )
  }
}
