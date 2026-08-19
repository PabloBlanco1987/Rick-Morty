import Foundation

/// A download queue with a limited number of slots and LIFO order — both decisions
/// against the same mistake: thinking requesting everything at once gets it sooner.
/// - Limited slots. URLSession opens six connections per host, so firing a hundred
///   images at once just queues them somewhere we don't control; a queue of our own can
///   actually be ordered.
/// - LIFO. A freed slot goes to the last image requested, not the first — on a fast
///   scroll that's the one on screen now, not one left behind ten screens ago. FIFO
///   would paint everything no longer visible before the one the user's looking at.
///
/// Needed because the view can't be trusted to tear down: `LazyVGrid` creates cells as
/// needed but doesn't discard them on scroll-past, so their tasks stay alive and
/// waiting. Ordering the queue is the only lever left.
///
/// Only slots are rationed here. How many requests per second can go out, and the brake
/// on a 429, live in `RateLimiter` — shared between images and JSON, so it can't belong
/// to just one queue.
actor DownloadQueue {
    typealias Work = () async throws(AppError) -> Data

    // Who's asking for the slot. A cell on screen jumps the line; a prefetch — images
    // for the page that just arrived but isn't visible yet — only goes in when nothing
    // visible is waiting.
    enum Priority: Sendable {
        case visible
        case prefetch
    }

    private let limit: Int
    private let pauseTimeout: Duration
    private var running = 0
    private var waiting: [Ticket] = []
    private var lastTicketID = 0

    // No new slots granted while paused. The view sets this while the scroll is
    // flinging (see CharacterListView) and clears it on stop. Expires on its own too —
    // if the view tears down mid-fling and never clears it, the queue can't stay dead
    // with the whole app's images stuck behind it.
    private(set) var isPaused = false
    private var pauseGeneration = 0

    private struct Ticket {
        let id: Int
        // Bool, not Void: says whether the slot was granted or the wait was cancelled,
        // which decides who's responsible for releasing it after.
        let continuation: CheckedContinuation<Bool, Never>
    }

    // internal so tests can check the queue drains instead of piling up dead waits
    var waitingCount: Int { waiting.count }

    init(limit: Int = 4, pauseTimeout: Duration = .seconds(1.5)) {
        self.limit = max(1, limit)
        self.pauseTimeout = pauseTimeout
    }

    func enqueue(priority: Priority = .visible, _ work: Work) async throws(AppError) -> Data {
        let granted = await acquire(priority)
        // A cancelled wait never held a slot — nothing to run, nothing to return.
        guard granted else { throw .cancelled }
        defer { release() }

        return try await work()
    }

    // MARK: - Pause

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        pauseGeneration += 1

        if paused {
            let generation = pauseGeneration
            // The task inherits the actor's isolation: sleeping doesn't block it, and
            // it wakes up still inside, so expirePause is called with no hop.
            Task {
                try? await Task.sleep(for: pauseTimeout)
                expirePause(generation)
            }
        } else {
            grantWhilePossible()
        }
    }

    // The generation keeps a stale timer from lifting a newer pause: pause, resume,
    // pause again leaves the first timer with nothing left to say.
    private func expirePause(_ generation: Int) {
        guard isPaused, pauseGeneration == generation else { return }
        isPaused = false
        grantWhilePossible()
    }

    private func grantWhilePossible() {
        while running < limit, let ticket = waiting.popLast() {
            running += 1
            ticket.continuation.resume(returning: true)
        }
    }

    // MARK: - Slots

    private func acquire(_ priority: Priority) async -> Bool {
        if !isPaused, running < limit {
            running += 1
            return true
        }

        lastTicketID += 1
        let id = lastTicketID

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let ticket = Ticket(id: id, continuation: continuation)
                switch priority {
                case .visible:
                    // At the end, where the next slot comes from: LIFO among visible.
                    waiting.append(ticket)
                case .prefetch:
                    // At the front, where nothing comes from while anything else is
                    // waiting — only goes in when no visible cell is.
                    waiting.insert(ticket, at: 0)
                }
            }
        } onCancel: {
            // Without this, a cell cancelled while waiting is never woken: under LIFO
            // its turn never comes, since someone newer is always ahead. The task
            // would sit parked forever.
            Task { await self.abandon(id) }
        }
    }

    private func release() {
        // While paused the slot is returned, not handed off — the only way to actually
        // stop requests going out. grantWhilePossible redistributes them on resume.
        guard !isPaused, let ticket = waiting.popLast() else {
            running -= 1
            return
        }
        // Handed off, not freed — so there's no window for someone else to cut in
        // ahead of whoever was already waiting.
        ticket.continuation.resume(returning: true)
    }

    private func abandon(_ id: Int) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(returning: false)
    }
}
