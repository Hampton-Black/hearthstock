import Foundation
import HearthstockCore
import Synchronization
import Testing
@testable import HearthstockLookup

/// Answers requests from a handler registered per test, found by a header the test's session adds. No test reaches
/// the network.
final class StubURLProtocol: URLProtocol {
    enum Reply: Sendable {
        case http(Int, String, headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    static let header = "X-Stub-ID"
    private static let handlers = Mutex<[String: @Sendable (URLRequest) -> Reply]>([:])

    /// A session configuration whose requests go to `handler`.
    static func configuration(_ handler: @escaping @Sendable (URLRequest) -> Reply) -> URLSessionConfiguration {
        let id = UUID().uuidString
        handlers.withLock { $0[id] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [header: id]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.header),
              let handler = Self.handlers.withLock({ $0[id] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch handler(request) {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .http(status, body, headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            if (300..<400).contains(status), let location = headers["Location"], let url = URL(string: location) {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: url), redirectResponse: response)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

private let userAgent = "Hearthstock/0.1.0 (hampton.j.black@gmail.com)"
private let beans = try! Barcode("051000012616")
private let foundBody = #"{"code": "0051000012616", "status": "success", "result": {"id": "product_found"}, "product": {"product_name": "Cream Of Mushroom Soup", "brands": "Campbell's"}}"#
private let notFoundBody = #"{"code": "0051000012616", "status": "failure", "result": {"id": "product_not_found"}}"#

/// Counts requests and records the last one.
private final class Recorder: Sendable {
    let requests = Mutex<[URLRequest]>([])
    var count: Int { requests.withLock { $0.count } }
    var last: URLRequest? { requests.withLock { $0.last } }
}

private func client(
    _ reply: @escaping @Sendable (URLRequest) -> StubURLProtocol.Reply, recorder: Recorder = Recorder(),
    budget: RequestBudget = RequestBudget(), now: @escaping @Sendable () -> Date = { Date() }
) -> OpenFoodFactsClient {
    OpenFoodFactsClient(
        userAgent: userAgent,
        configuration: StubURLProtocol.configuration { request in
            recorder.requests.withLock { $0.append(request) }
            return reply(request)
        },
        budget: budget, now: now)
}

@Suite struct OpenFoodFactsClientTests {
    @Test func foundAndNotFound() async {
        #expect(await client { _ in .http(200, foundBody) }.lookup(beans)
            == .found(LookedUpProduct(name: "Cream Of Mushroom Soup", brand: "Campbell's")))
        #expect(await client { _ in .http(404, notFoundBody) }.lookup(beans) == .notFound)
    }

    @Test(arguments: [
        (StubURLProtocol.Reply.failure(.timedOut), LookupResult.unavailable(.timedOut)),
        (.failure(.notConnectedToInternet), .unavailable(.offline)),
        (.failure(.networkConnectionLost), .unavailable(.offline)),
        (.failure(.cannotFindHost), .unavailable(.offline)),
        (.http(429, "Too many requests"), .unavailable(.rateLimited)),
        (.http(503, "Service unavailable"), .unavailable(.serverError)),
        (.http(200, "<html>not json</html>"), .unavailable(.serverError)),
    ])
    func trouble(reply: StubURLProtocol.Reply, expected: LookupResult) async {
        #expect(await client { _ in reply }.lookup(beans) == expected)
    }

    @Test func sendsTheBarcodeTheFieldsAndTheUserAgentOnly() async throws {
        let recorder = Recorder()
        _ = await client({ _ in .http(200, foundBody) }, recorder: recorder).lookup(beans)
        let request = try #require(recorder.last)
        let url = try #require(request.url)
        #expect(url.host() == "world.openfoodfacts.org")
        #expect(url.path() == "/api/v3/product/0051000012616")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [URLQueryItem(name: "fields", value: OpenFoodFactsClient.fields.joined(separator: ","))])
        #expect(request.value(forHTTPHeaderField: "User-Agent") == userAgent)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
    }

    @Test func aRedirectIsNotFollowed() async {
        let recorder = Recorder()
        let lookup = client({ _ in
            .http(302, "", headers: ["Location": "https://world.openbeautyfacts.org/api/v3/product/0051000012616"])
        }, recorder: recorder)
        #expect(await lookup.lookup(beans) == .notFound)
        #expect(recorder.count == 1)
    }

    @Test func theRateCapAnswersWithoutARequest() async {
        let recorder = Recorder()
        let lookup = client(
            { _ in .http(404, notFoundBody) }, recorder: recorder, budget: RequestBudget(limit: 2, window: 60),
            now: { Date(timeIntervalSince1970: 0) })
        #expect(await lookup.lookup(beans) == .notFound)
        #expect(await lookup.lookup(beans) == .notFound)
        #expect(await lookup.lookup(beans) == .unavailable(.rateLimited))
        #expect(recorder.count == 2)
    }

    @Test func theBudgetRefillsAsTheWindowMoves() {
        var budget = RequestBudget(limit: 2, window: 60)
        let start = Date(timeIntervalSince1970: 0)
        let taken = [0, 10, 59, 60, 65, 70].map { budget.take(at: start.addingTimeInterval($0)) }
        // The third is over the cap; at 60 s the first has aged out; at 70 s the second has.
        #expect(taken == [true, true, false, true, false, true])
    }

    @Test func theDefaultCapIsBelowOpenFoodFactsLimit() {
        #expect(RequestBudget.defaultLimit < 15)
        #expect(OpenFoodFactsClient.timeout <= 4)
    }
}

// MARK: - Caching

/// A lookup cache in memory.
private actor MemoryCache: LookupCacheRepository {
    var entries: [Barcode: CachedLookup] = [:]
    func get(_ barcode: Barcode) -> CachedLookup? { entries[barcode] }
    func put(_ entry: CachedLookup) { entries[entry.barcode] = entry }
    func count() -> Int { entries.count }
    func clear() { entries = [:] }
}

/// An online service that answers from a script and counts calls.
private final class ScriptedLookup: ProductLookupService, Sendable {
    let answers: Mutex<[LookupResult]>
    let calls = Mutex(0)
    init(_ answers: [LookupResult]) { self.answers = Mutex(answers) }
    func lookup(_ barcode: Barcode) async -> LookupResult {
        calls.withLock { $0 += 1 }
        return answers.withLock { $0.isEmpty ? .notFound : $0.removeFirst() }
    }
    var callCount: Int { calls.withLock { $0 } }
}

private final class Switch: Sendable {
    let on = Mutex(true)
    var isOn: Bool { on.withLock { $0 } }
    func set(_ value: Bool) { on.withLock { $0 = value } }
}

private let soup = LookedUpProduct(name: "Cream Of Mushroom Soup", brand: "Campbell's")
private let fetched = Date(timeIntervalSince1970: 1_800_000_000)

@Suite struct CachingProductLookupTests {
    private func caching(_ online: ScriptedLookup, cache: MemoryCache = MemoryCache(), switch toggle: Switch = Switch())
        -> CachingProductLookup
    {
        CachingProductLookup(online: online, cache: cache, isEnabled: { toggle.isOn }, now: { fetched })
    }

    @Test func aSecondLookupOfTheSameBarcodeMakesNoRequest() async {
        let online = ScriptedLookup([.found(soup)])
        let cache = MemoryCache()
        let lookup = caching(online, cache: cache)
        #expect(await lookup.lookup(beans) == .found(soup))
        #expect(await lookup.lookup(beans) == .found(soup))
        #expect(online.callCount == 1)
        #expect(await cache.get(beans) == CachedLookup(barcode: beans, outcome: .found(soup), fetchedAt: fetched))
    }

    @Test func aSavedNotFoundMakesNoRequest() async {
        let online = ScriptedLookup([.notFound, .found(soup)])
        let lookup = caching(online)
        #expect(await lookup.lookup(beans) == .notFound)
        #expect(await lookup.lookup(beans) == .notFound)
        #expect(online.callCount == 1)
    }

    @Test(arguments: [LookupUnavailableReason.offline, .timedOut, .rateLimited, .serverError])
    func unavailableIsNotSavedAndTheNextLookupTriesAgain(reason: LookupUnavailableReason) async {
        let online = ScriptedLookup([.unavailable(reason), .found(soup)])
        let cache = MemoryCache()
        let lookup = caching(online, cache: cache)
        #expect(await lookup.lookup(beans) == .unavailable(reason))
        #expect(await cache.count() == 0)
        #expect(await lookup.lookup(beans) == .found(soup))
        #expect(online.callCount == 2)
    }

    @Test func aSavedAnswerIsServedWithLookupsSwitchedOff() async {
        let online = ScriptedLookup([.found(soup)])
        let toggle = Switch()
        let lookup = caching(online, switch: toggle)
        _ = await lookup.lookup(beans)
        toggle.set(false)
        #expect(await lookup.lookup(beans) == .found(soup))
        #expect(online.callCount == 1)
    }

    @Test func switchedOffAnUnsavedBarcodeIsNeverAskedAbout() async {
        let online = ScriptedLookup([.found(soup)])
        let toggle = Switch()
        toggle.set(false)
        let cache = MemoryCache()
        let lookup = caching(online, cache: cache, switch: toggle)
        #expect(await lookup.lookup(beans) == .unavailable(.switchedOff))
        #expect(await lookup.refresh(beans) == .unavailable(.switchedOff))
        #expect(online.callCount == 0)
        #expect(await cache.count() == 0)
    }

    @Test func refreshAsksAgainAndReplacesTheSavedAnswer() async {
        let online = ScriptedLookup([.notFound, .found(soup)])
        let cache = MemoryCache()
        let lookup = caching(online, cache: cache)
        #expect(await lookup.lookup(beans) == .notFound)
        #expect(await lookup.refresh(beans) == .found(soup))
        #expect(online.callCount == 2)
        #expect(await lookup.lookup(beans) == .found(soup))
        #expect(online.callCount == 2)
    }

    @Test func clearingTheCacheSendsTheNextLookupOnline() async {
        let online = ScriptedLookup([.found(soup), .found(soup)])
        let cache = MemoryCache()
        let lookup = caching(online, cache: cache)
        _ = await lookup.lookup(beans)
        await cache.clear()
        _ = await lookup.lookup(beans)
        #expect(online.callCount == 2)
    }

    @Test func theDisabledServiceNeverAsks() async {
        #expect(await DisabledLookupService().lookup(beans) == .unavailable(.switchedOff))
    }
}
