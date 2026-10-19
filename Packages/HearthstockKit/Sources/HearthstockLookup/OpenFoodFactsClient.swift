import Foundation
import HearthstockCore

/// Asks Open Food Facts about one barcode: a single GET to the v3 product endpoint with only the fields
/// `OpenFoodFacts.decode` reads. It sends the barcode and the User-Agent, nothing else: an ephemeral session, so no
/// cookies or cache, and redirects aren't followed (a redirect points at a sister database for non-food items).
///
/// It never throws. Offline, a timeout, its own rate cap or a server error all come back as `unavailable`, within
/// about `timeout` seconds, so a weak signal never stalls a pantry walk.
public actor OpenFoodFactsClient: ProductLookupService {
    /// The fields `OpenFoodFacts.decode` reads, and nothing more.
    public static let fields = [
        "code", "product_name", "product_name_en", "brands", "quantity", "product_quantity", "product_quantity_unit",
        "serving_quantity", "serving_quantity_unit", "serving_size", "nutriments", "categories_tags",
    ]
    public static let endpoint = URL(string: "https://world.openfoodfacts.org/api/v3/product/")!
    public static let timeout: TimeInterval = 4

    private let session: URLSession
    private var budget: RequestBudget
    private let now: @Sendable () -> Date

    /// `userAgent` is "Hearthstock/<version> (<contact>)" (Decision 9). `configuration` is for tests; it defaults to
    /// an ephemeral one.
    public init(
        userAgent: String,
        configuration: URLSessionConfiguration = .ephemeral,
        budget: RequestBudget = RequestBudget(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let configuration = configuration
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        var headers = configuration.httpAdditionalHeaders ?? [:]
        headers["User-Agent"] = userAgent
        configuration.httpAdditionalHeaders = headers
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        self.budget = budget
        self.now = now
    }

    public static func request(for barcode: Barcode) -> URLRequest {
        var components = URLComponents(
            url: endpoint.appending(path: barcode.rawValue), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: fields.joined(separator: ","))]
        return URLRequest(url: components.url!)
    }

    public func lookup(_ barcode: Barcode) async -> LookupResult {
        guard budget.take(at: now()) else { return .unavailable(.rateLimited) }
        do {
            let (data, response) = try await session.data(for: Self.request(for: barcode))
            guard let http = response as? HTTPURLResponse else { return .unavailable(.serverError) }
            return OpenFoodFacts.decode(data, httpStatus: http.statusCode)
        } catch let error as URLError {
            return .unavailable(Self.reason(error))
        } catch {
            return .unavailable(.serverError)
        }
    }

    static func reason(_ error: URLError) -> LookupUnavailableReason {
        switch error.code {
        case .timedOut: .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .callIsActive:
            .offline
        default: .serverError
        }
    }

    /// Hands the redirect response back instead of following it.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }
}

/// The client's own cap on requests per minute, kept below Open Food Facts' published limit of 15 product reads per
/// minute per IP (Decision 11). Over the cap a lookup is `unavailable(.rateLimited)` without a request.
public struct RequestBudget: Sendable {
    public static let defaultLimit = 10
    public let limit: Int
    public let window: TimeInterval
    private var recent: [Date] = []

    public init(limit: Int = Self.defaultLimit, window: TimeInterval = 60) {
        self.limit = limit
        self.window = window
    }

    /// Spends one request at `time` if fewer than `limit` were spent in the `window` before it.
    public mutating func take(at time: Date) -> Bool {
        recent.removeAll { time.timeIntervalSince($0) >= window }
        guard recent.count < limit else { return false }
        recent.append(time)
        return true
    }
}
