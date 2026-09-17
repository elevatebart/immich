import Foundation
import SwiftUI
import WidgetKit

let IMMICH_SHARE_GROUP = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as! String

enum WidgetError: Error, Codable {
  case noLogin
  case fetchFailed
  case albumNotFound
  case noAssetsAvailable
  case noMatchingAssets
}

enum FetchError: Error {
  case unableToResize
  case invalidImage
  case invalidURL
  case fetchFailed
}

extension WidgetError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .noLogin:
      return "Login to Immich"

    case .fetchFailed:
      return "Unable to connect to Immich"

    case .albumNotFound:
      return "Album not found"

    case .noAssetsAvailable:
      return "No assets available"

    case .noMatchingAssets:
      return "No assets matched the selected filters"
    }
  }
}

enum AssetType: String, Codable {
  case image = "IMAGE"
  case video = "VIDEO"
  case audio = "AUDIO"
  case other = "OTHER"
}

struct ExifInfo: Codable {
  let exifImageWidth: Int?
  let exifImageHeight: Int?
  let orientation: String?
}

struct Asset: Codable {
  let id: String
  let type: AssetType
  /// Already orientation corrected by the server, and present on the plain
  /// asset response, so this needs no `withExif`. Absent on older servers.
  var width: Int? = nil
  var height: Int? = nil
  var exifInfo: ExifInfo? = nil

  var deepLink: URL? {
    return URL(string: "immich://asset?id=\(id)")
  }

  /// Dimensions as rendered, falling back to raw EXIF with the rotation applied
  /// by hand. Mirrors `getDimensions` in server/src/utils/asset.util.ts.
  var displaySize: (width: Int, height: Int)? {
    if let width, let height, width > 0, height > 0 {
      return (width, height)
    }

    guard let exifInfo, let width = exifInfo.exifImageWidth,
      let height = exifInfo.exifImageHeight, width > 0, height > 0
    else {
      return nil
    }

    let rotated = [5, 6, 7, 8, -90, 90].contains(Int(exifInfo.orientation ?? "") ?? 0)
    return rotated ? (height, width) : (width, height)
  }
}

/// Sizes served by the asset media endpoints, smallest first.
enum ImageSize: String, Codable {
  case thumbnail
  case preview
  case fullsize
  case original
}

struct SearchFilter: Codable {
  var type = AssetType.image
  var size = 1
  var albumIds: [String] = []
  var isFavorite: Bool? = nil
  var withExif: Bool = false
}

struct SmartSearchFilter: Codable {
  var query: String
  var type = AssetType.image
  var size = 25
  var albumIds: [String] = []
  var isFavorite: Bool? = nil
}

struct SearchResult: Codable {
  struct AssetResults: Codable {
    let items: [Asset]
  }

  let assets: AssetResults
}

struct MemoryResult: Codable {
  let id: String
  var assets: [Asset]
  let type: String

  struct MemoryData: Codable {
    let year: Int
  }

  let data: MemoryData
}

struct Album: Codable, Equatable {
  let id: String
  let albumName: String

  static let NONE = Album(id: "NONE", albumName: "None")
  static let FAVORITES = Album(id: "FAVORITES", albumName: "Favorites")

  var filter: SearchFilter {
    switch self {
    case Album.NONE:
      return SearchFilter()
    case Album.FAVORITES:
      return SearchFilter(isFavorite: true)

    // regular album
    default:
      return SearchFilter(albumIds: [id])
    }
  }

  var isVirtual: Bool {
    switch self {
    case Album.NONE, Album.FAVORITES:
      return true
    default:
      return false
    }
  }
}

// MARK: API

class ImmichAPI {
  typealias CustomHeaders = [String:String]
  struct ServerConfig {
    let serverEndpoint: String
    let sessionKey: String
    let customHeaders: CustomHeaders
  }
  
  let serverConfig: ServerConfig

  init() async throws {
    // fetch the credentials from the UserDefaults store that dart placed here
    guard let defaults = UserDefaults(suiteName: IMMICH_SHARE_GROUP),
      let serverURL = defaults.string(forKey: "widget_server_url"),
      let sessionKey = defaults.string(forKey: "widget_auth_token")
    else {
      throw WidgetError.noLogin
    }

    if serverURL == "" || sessionKey == "" {
      throw WidgetError.noLogin
    }
    
    // custom headers come in the form of KV pairs in JSON
    var customHeadersJSON = (defaults.string(forKey: "widget_custom_headers") ?? "")
    var customHeaders: CustomHeaders = [:]
    
    if customHeadersJSON != "",
       let parsedHeaders = try? JSONDecoder().decode(CustomHeaders.self, from: customHeadersJSON.data(using: .utf8)!) {
      customHeaders = parsedHeaders
    }

    serverConfig = ServerConfig(
      serverEndpoint: serverURL,
      sessionKey: sessionKey,
      customHeaders: customHeaders
    )
  }

  private func buildRequestURL(
    serverConfig: ServerConfig,
    endpoint: String,
    params: [URLQueryItem] = []
  ) -> URL? {
    guard let baseURL = URL(string: serverConfig.serverEndpoint) else {
      fatalError("Invalid base URL")
    }

    // Combine the base URL and API path
    let fullPath = baseURL.appendingPathComponent(
      endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    )

    // Add the session key as a query parameter
    var components = URLComponents(
      url: fullPath,
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
      URLQueryItem(name: "sessionKey", value: serverConfig.sessionKey)
    ]
    components?.queryItems?.append(contentsOf: params)

    return components?.url
  }
  
  func applyCustomHeaders(for request: inout URLRequest) {
    for (header, value) in serverConfig.customHeaders {
      request.addValue(value, forHTTPHeaderField: header)
    }
  }

  func fetchSearchResults(with filters: SearchFilter = Album.NONE.filter)
    async throws
    -> [Asset]
  {
    // get URL
    guard
      let searchURL = buildRequestURL(
        serverConfig: serverConfig,
        endpoint: "/search/random"
      )
    else {
      throw URLError(.badURL)
    }

    var request = URLRequest(url: searchURL)
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(filters)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    applyCustomHeaders(for: &request)
    
    let (data, _) = try await URLSession.shared.data(for: request)

    // decode data
    return try JSONDecoder().decode([Asset].self, from: data)
  }

  /// CLIP search, so this needs Smart Search enabled on the server.
  func fetchSmartSearchResults(with filter: SmartSearchFilter) async throws -> [Asset] {
    guard
      let searchURL = buildRequestURL(
        serverConfig: serverConfig,
        endpoint: "/search/smart"
      )
    else {
      throw URLError(.badURL)
    }

    var request = URLRequest(url: searchURL)
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(filter)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    applyCustomHeaders(for: &request)

    let (data, _) = try await URLSession.shared.data(for: request)

    return try JSONDecoder().decode(SearchResult.self, from: data).assets.items
  }

  func fetchMemory(for date: Date) async throws -> [MemoryResult] {
    // get URL
    let localDay = date.formatted(
      Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash)
    )
    let memoryParams = [URLQueryItem(name: "for", value: localDay)]
    guard
      let searchURL = buildRequestURL(
        serverConfig: serverConfig,
        endpoint: "/memories",
        params: memoryParams
      )
    else {
      throw URLError(.badURL)
    }

    var request = URLRequest(url: searchURL)
    request.httpMethod = "GET"
    applyCustomHeaders(for: &request)

    let (data, _) = try await URLSession.shared.data(for: request)

    // decode data
    return try JSONDecoder().decode([MemoryResult].self, from: data)
  }

  func fetchImage(asset: Asset) async throws(FetchError) -> UIImage {
    let thumbnailParams = [URLQueryItem(name: "size", value: "preview"), URLQueryItem(name: "edited", value: "true")]
    let assetEndpoint = "/assets/" + asset.id + "/thumbnail"

    guard
      let fetchURL = buildRequestURL(
        serverConfig: serverConfig,
        endpoint: assetEndpoint,
        params: thumbnailParams
      )
    else {
      throw .invalidURL
    }

    guard let imageSource = CGImageSourceCreateWithURL(fetchURL as CFURL, nil)
    else {
      throw .invalidURL
    }

    let decodeOptions: [NSString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: 512,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]

    guard
      let thumbnail = CGImageSourceCreateThumbnailAtIndex(
        imageSource,
        0,
        decodeOptions as CFDictionary
      )
    else {
      throw .fetchFailed
    }

    return UIImage(cgImage: thumbnail)
  }

  /// Downloads an asset without decoding it, so callers can hand the bytes off
  /// to Shortcuts without paying the extension's memory ceiling for a bitmap.
  func fetchImageData(asset: Asset, size: ImageSize) async throws(FetchError)
    -> (data: Data, mimeType: String)
  {
    let isOriginal = size == .original
    let endpoint = "/assets/" + asset.id + (isOriginal ? "/original" : "/thumbnail")
    var params = [URLQueryItem(name: "edited", value: "true")]
    if !isOriginal {
      params.append(URLQueryItem(name: "size", value: size.rawValue))
    }

    guard
      let fetchURL = buildRequestURL(
        serverConfig: serverConfig,
        endpoint: endpoint,
        params: params
      )
    else {
      throw .invalidURL
    }

    var request = URLRequest(url: fetchURL)
    request.httpMethod = "GET"
    applyCustomHeaders(for: &request)

    guard let (data, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
    else {
      throw .fetchFailed
    }

    let mimeType =
      http.value(forHTTPHeaderField: "Content-Type")?
      .components(separatedBy: ";").first?
      .trimmingCharacters(in: .whitespaces) ?? "application/octet-stream"

    return (data, mimeType)
  }

  func fetchAlbums() async throws -> [Album] {
    // get URL
    guard
      let searchURL = buildRequestURL(
        serverConfig: serverConfig,
        endpoint: "/albums"
      )
    else {
      throw URLError(.badURL)
    }

    var request = URLRequest(url: searchURL)
    request.httpMethod = "GET"
    applyCustomHeaders(for: &request)
    
    let (data, _) = try await URLSession.shared.data(for: request)

    // decode data
    return try JSONDecoder().decode([Album].self, from: data)
  }
}

// We need a shared cache for albums to efficiently handle the album picker queries
actor AlbumCache {
  static let shared = AlbumCache()

  private var api: ImmichAPI? = nil
  private var albums: [Album]? = nil

  func getAlbums(refresh: Bool = false) async throws -> [Album] {
    // Check the API before we try to show cached albums
    // Sometimes iOS caches this object and keeps it around
    // even after nuking the timeline

    api = try? await ImmichAPI()

    guard api != nil else {
      throw WidgetError.noLogin
    }

    if let albums, !refresh {
      return albums
    }

    let fetched = try await api!.fetchAlbums()
    albums = fetched
    return fetched
  }
}
