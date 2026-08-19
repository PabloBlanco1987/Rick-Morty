import Foundation

/// A screen's state, in a single value. The usual alternative — separate isLoading,
/// items, errorMessage — lets you write states that don't exist: loading and failed at
/// once, or an empty list with no way to tell "nothing here" from "hasn't arrived yet."
/// An enum makes those combinations impossible to even type, and turns the view into
/// an exhaustive switch the compiler forces to cover entirely.
enum ViewState<Value> {
    // Nothing requested yet. Different from .loading: on returning to the screen,
    // this is what says whether to load or whether something's already loaded.
    case idle
    case loading
    case loaded(Value)
    // Went fine and there's nothing to show. A result, not a failure — and what's
    // painted looks nothing like an error screen, so it gets its own case.
    case empty
    case failed(AppError)
}

extension ViewState: Equatable where Value: Equatable {}
extension ViewState: Sendable where Value: Sendable {}

extension ViewState {
    var value: Value? {
        guard case .loaded(let value) = self else { return nil }
        return value
    }
}
