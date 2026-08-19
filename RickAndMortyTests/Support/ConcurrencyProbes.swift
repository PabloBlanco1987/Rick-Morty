import Foundation

/// An async gate: whoever calls `wait()` blocks until the test opens it.
///
/// Used to freeze an in-flight operation and inspect what the app does meanwhile. The
/// alternative — sleep 50ms and hope — is the usual recipe for tests that flake one
/// time in thirty on CI, so there are no timers here: only rendezvous.
actor AsyncGate {
    private var isOpen = false
    private var hasBeenReached = false
    private var blocked: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []

    // Called by the code under test.
    func wait() async {
        hasBeenReached = true
        watchers.forEach { $0.resume() }
        watchers.removeAll()

        guard !isOpen else { return }
        await withCheckedContinuation { blocked.append($0) }
    }

    // Called by the test: returns as soon as someone has reached the gate, so from
    // then on the operation is known to be frozen inside.
    func waitUntilReached() async {
        guard !hasBeenReached else { return }
        await withCheckedContinuation { watchers.append($0) }
    }

    // Opens and stays open: anyone arriving after this no longer blocks.
    func open() {
        isOpen = true
        blocked.forEach { $0.resume() }
        blocked.removeAll()
    }
}

/// Records waits instead of actually sleeping, so what's asserted is the decision —
/// how long and when — not the clock, keeping the whole suite in milliseconds.
actor SleepRecorder {
    private(set) var durations: [Duration] = []

    func record(_ duration: Duration) { durations.append(duration) }
}

/// Records the order in which each request was handled.
actor OrderRecorder {
    private(set) var ids: [Int] = []

    func record(_ id: Int) { ids.append(id) }
}

/// How many things were in flight at once. Distinguishes a limit that's actually
/// honored from one that's merely written down.
actor ConcurrencyProbe {
    private(set) var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() { current -= 1 }
}
