import AppIntents

extension Person: @unchecked Sendable, AppEntity, Identifiable {

  struct PersonQuery: EntityQuery {
    func entities(for identifiers: [Person.ID]) async throws -> [Person] {
      return await suggestedEntities().filter {
        identifiers.contains($0.id)
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
