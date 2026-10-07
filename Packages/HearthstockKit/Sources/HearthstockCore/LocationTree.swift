import Foundation

/// The parent/child structure of a site's locations.
public enum LocationTree {
    /// Every location's path from its top-level ancestor, depth first: parents before children, siblings by
    /// name. Locations in a cycle, or under a missing parent, are left out.
    public static func paths(_ locations: [Location]) -> [[Location]] {
        let ids = Set(locations.map(\.id))
        let children = Dictionary(grouping: locations, by: { location in
            location.parentID.flatMap { ids.contains($0) ? $0 : nil }
        })
        var result: [[Location]] = []
        func visit(_ parent: LocationID?, path: [Location]) {
            for kid in (children[parent] ?? []).sorted(by: nameOrder) {
                let kidPath = path + [kid]
                result.append(kidPath)
                visit(kid.id, path: kidPath)
            }
        }
        visit(nil, path: [])  // roots: no parent, or a parent that isn't in the list
        return result
    }

    /// The locations below `id`, at any depth. Stops at a cycle.
    public static func descendants(of id: LocationID, in locations: [Location]) -> Set<LocationID> {
        let children = Dictionary(grouping: locations, by: \.parentID)
        var found: Set<LocationID> = []
        var queue = [id]
        while let next = queue.popLast() {
            for child in children[next] ?? [] where child.id != id && found.insert(child.id).inserted {
                queue.append(child.id)
            }
        }
        return found
    }

    /// Where `location` can move: any location of its site except itself and those below it, so a move can never
    /// make a loop. In `paths` order.
    public static func possibleParents(for location: Location, in locations: [Location]) -> [[Location]] {
        let excluded = descendants(of: location.id, in: locations).union([location.id])
        return paths(locations.filter { $0.siteID == location.siteID })
            .filter { path in !path.contains { excluded.contains($0.id) } }
    }

    private static func nameOrder(_ lhs: Location, _ rhs: Location) -> Bool {
        let order = lhs.name.localizedStandardCompare(rhs.name)
        return order == .orderedSame ? lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString : order == .orderedAscending
    }
}
