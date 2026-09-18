import AppIntents

extension Person: @unchecked Sendable, AppEntity, Identifiable {

  // EntityStringQuery rather than EntityQuery: a library can have hundreds of
  // named faces, which is a search field rather than a scroll.
  struct PersonQuery: EntityStringQuery {
    func entities(for identifiers: [Person.ID]) async throws -> [Person] {
      return await suggestedEntities().filter {
        identifiers.contains($0.id)
      }
    }

    func entities(matching string: String) async throws -> [Person] {
      return await suggestedEntities().filter {
        $0.name.localizedCaseInsensitiveContains(string)
      }
    }

    func suggestedEntities() async -> [Person] {
      return (try? await PersonCache.shared.getPeople()) ?? []
    }
  }

  static var defaultQuery = PersonQuery()
  static var typeDisplayRepresentation = TypeDisplayRepresentation(
    name: "Person"
  )

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}
