import Foundation

/// Guesses a shelf-life profile (and water) from a product's name, for when Open Food Facts' categories say nothing
/// (Slice 5 Decision 6). The keywords are bundled data, `name-keyword-profiles.json`, editable like the shelf-life
/// table. A guess is only ever a starting point the person sees and can change.
public struct NameProfileGuesser: Hashable, Sendable {
    /// One keyword or phrase. With no profile, it only stops the shorter keywords inside it from matching. A veto
    /// stops any guess at all: "corn flakes" stays Other food, the conservative default.
    public struct Keyword: Hashable, Sendable, Codable {
        public var phrase: String
        public var profile: ShelfLifeProfileKey?
        /// Water, or nil for food.
        public var category: Category?
        /// The name or the size must also say "oz" or "can".
        public var needsCanCue: Bool?
        public var vetoes: Bool?

        public init(
            phrase: String, profile: ShelfLifeProfileKey?, category: Category? = nil, needsCanCue: Bool? = nil,
            vetoes: Bool? = nil
        ) {
            self.phrase = phrase
            self.profile = profile
            self.category = category
            self.needsCanCue = needsCanCue
            self.vetoes = vetoes
        }
    }

    /// What the name suggests, and the phrase that said so.
    public struct Guess: Hashable, Sendable {
        public var profile: ShelfLifeProfileKey
        public var category: Category
        public var phrase: String

        public init(profile: ShelfLifeProfileKey, category: Category, phrase: String) {
            self.profile = profile
            self.category = category
            self.phrase = phrase
        }
    }

    public let keywords: [Keyword]
    /// Phrases as words, longest first, so a phrase uses up its words before a shorter keyword can match them.
    private let ordered: [(words: [String], keyword: Keyword)]

    public init(keywords: [Keyword]) {
        self.keywords = keywords
        ordered = keywords.map { (Self.words($0.phrase), $0) }
            .filter { !$0.0.isEmpty }
            .sorted { lhs, rhs in
                lhs.words.count != rhs.words.count ? lhs.words.count > rhs.words.count
                    : lhs.keyword.phrase < rhs.keyword.phrase
            }
    }

    public static func == (lhs: NameProfileGuesser, rhs: NameProfileGuesser) -> Bool { lhs.keywords == rhs.keywords }
    public func hash(into hasher: inout Hasher) { hasher.combine(keywords) }

    private struct File: Decodable {
        var keywords: [Keyword]
    }

    public init(jsonData: Data) throws {
        self.init(keywords: try JSONDecoder().decode(File.self, from: jsonData).keywords)
    }

    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missingResource

        public var description: String { "name-keyword-profiles.json isn't in the app bundle" }
    }

    /// No guesses: products without categories keep their category's default profile.
    public static let empty = NameProfileGuesser(keywords: [])

    public static func bundled() throws -> NameProfileGuesser {
        guard let url = Bundle.module.url(forResource: "name-keyword-profiles", withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try NameProfileGuesser(jsonData: Data(contentsOf: url))
    }

    /// The profile `name` suggests, or nil when no keyword matches a profile in `table`. Whole words only, ignoring
    /// case and accents. Several matches take the shortest window (the conservative guess), ties by key; a food
    /// match beats a water one. `quantityLabel` ("15.25 oz") only serves as the can cue.
    public func guess(name: String, quantityLabel: String? = nil, in table: ShelfLifeProfileTable) -> Guess? {
        var words = Self.words(name)
        guard !words.isEmpty else { return nil }
        let cueWords = Set(words + Self.words(quantityLabel ?? ""))
        let hasCanCue = !cueWords.isDisjoint(with: ["oz", "can", "cans", "canned"])

        var matches: [(keyword: Keyword, profile: ShelfLifeProfile)] = []
        for (phrase, keyword) in ordered {
            var index = 0
            while index + phrase.count <= words.count {
                guard Array(words[index..<index + phrase.count]) == phrase else {
                    index += 1
                    continue
                }
                // Used up: a shorter keyword can't match these words again.
                for offset in 0..<phrase.count { words[index + offset] = "" }
                index += phrase.count
                if keyword.vetoes == true { return nil }
                if keyword.needsCanCue == true, !hasCanCue { continue }
                if let key = keyword.profile, let profile = table[key] { matches.append((keyword, profile)) }
            }
        }
        let food = matches.filter { ($0.keyword.category ?? .food) == .food }
        let candidates = food.isEmpty ? matches : food
        guard let best = candidates.min(by: { lhs, rhs in
            let l = OFFCategoryMap.windowMonths(lhs.profile), r = OFFCategoryMap.windowMonths(rhs.profile)
            return l != r ? l < r : lhs.profile.key.rawValue < rhs.profile.key.rawValue
        }) else { return nil }
        return Guess(profile: best.profile.key, category: best.keyword.category ?? .food, phrase: best.keyword.phrase)
    }

    /// Lowercased, accent-free words: "Crème brûlée, 4 oz" → ["creme", "brulee", "4", "oz"].
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
