import Foundation
import HearthstockCore

/// Where a screen's live data stands.
enum FeedPhase: Equatable {
    case loading
    case live
    /// The subscription failed; the screen shows this in place of its content.
    case failed(String)
}

/// The one view-model pattern every screen uses: a `@MainActor @Observable` class, started from `.task`, that
/// subscribes to `observeRunwayInputs(siteID:)`, keeps the latest snapshot and recomputes its Core results from it
/// and `today`. Writes go through the repositories and come back through the subscription; nothing patches its own
/// copy. Cancelling the task ends the subscription.
@MainActor
protocol RunwayInputsModel: AnyObject {
    var phase: FeedPhase { get set }
    var inputs: RunwayInputs? { get set }
    var today: CalendarDate { get set }
    /// Rebuild the derived values from `inputs` and `today`.
    func recompute()
}

extension RunwayInputsModel {
    /// Runs until the calling task is cancelled.
    func subscribe(_ services: AppServices, siteID: SiteID) async {
        do {
            for try await snapshot in services.runwayInputs.observeRunwayInputs(siteID: siteID) {
                inputs = snapshot
                phase = .live
                recompute()
            }
        } catch is CancellationError {
        } catch {
            phase = .failed(ErrorText.describe(error))
        }
    }

    /// Call from `.onChange(of: today, initial: true)`.
    func setToday(_ day: CalendarDate) {
        guard day != today else { return }
        today = day
        recompute()
    }
}
