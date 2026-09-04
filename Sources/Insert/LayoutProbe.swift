import AppKit
import Foundation

/// A stall detector for the main thread, off unless asked for.
///
/// It exists to settle one question a `sample` cannot: when the window freezes,
/// is that **one enormous layout pass**, or a **runaway invalidation loop** —
/// SwiftUI re-entering the same update because something the update itself
/// writes dirties the graph again? A snapshot of the stack looks identical
/// either way; the difference is how many times the work inside it is repeated.
///
/// **Counting card bodies alone cannot answer that, and the first cut of this
/// file did exactly that.** Fable 5.1, asked for a second opinion on the trace,
/// named the hole: a loop through `CollapsibleMarkdown`'s four measured `@State`s
/// re-evaluates *its* body and not the card's, and a purely geometric re-run
/// (`sizeThatFits` → `placeSubviews`) evaluates **no** body at all — so
/// "bodies ≈ cards on screen ⇒ single pass" was a false inference. The counters
/// below therefore straddle the three layers a repeat can hide in: view bodies,
/// the geometry writes that are the candidate feedback edges, and the text
/// measurement that runs with no body evaluation at all.
///
/// **Off by default and free when off** — `isOn` is resolved once and every
/// entry point returns on a `let Bool` — because the freeze that prompted this
/// happened in the *release* build, so a dev-only probe would not have caught
/// it. Turn it on for whichever build is misbehaving:
///
/// ```
/// defaults write com.alejandrolacasa.insert layoutProbe -bool YES     # release
/// defaults write com.alejandrolacasa.insert.dev layoutProbe -bool YES # dev
/// ```
///
/// It writes to `/tmp/insert-layout.log`, which is what the maintainer's own
/// tooling can read back.
///
/// **Reading the log.** `bodies=` counts view-body evaluations, `geo=` geometry
/// writes, `measure=` text measurements. Against a window showing N cards:
/// numbers at or near N are one pass; numbers at a multiple of N are that many
/// passes (2–3 is normal on first layout — each card lands several geometry
/// writes); numbers *unbounded* against N are the loop. A `stalling` line with
/// no `stall` line after it is a freeze that was force-quit.
enum LayoutProbe {
    /// Turns longer than this are worth a line. 250ms is well past a dropped
    /// frame and well short of anything a person calls a freeze, so a log that
    /// fills up is itself the finding.
    private static let stallThreshold: TimeInterval = 0.25

    /// How long the watchdog waits before reporting a turn that hasn't ended.
    private static let watchdogThreshold: TimeInterval = 2

    static let isOn: Bool =
        UserDefaults.standard.bool(forKey: "layoutProbe")
        || ProcessInfo.processInfo.environment["INSERT_LAYOUT_PROBE"] == "1"

    private static let logURL = URL(fileURLWithPath: "/tmp/insert-layout.log")
    private static let launched = Date()

    /// Locked rather than main-actor-isolated, because the **watchdog reads it
    /// off the main thread** — which is the whole point of the watchdog: the
    /// main thread is wedged, so it cannot report on itself. A locked class is
    /// also what Swift 6 strict concurrency wants here, the shape `MemoCache`
    /// already uses. Contention is nil (one writer, one reader every 500ms) and
    /// the whole thing is inert when off.
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var turnStart = CFAbsoluteTimeGetCurrent()
        private var counts: [Counter: [String: Int]] = [:]
        private var reportedStalling = false
        private var observer: CFRunLoopObserver?
        private var watchdog: DispatchSourceTimer?

        func bump(_ counter: Counter, _ name: String) {
            lock.lock()
            counts[counter, default: [:]][name, default: 0] += 1
            lock.unlock()
        }

        /// Closes the current turn and opens the next. Returns how long it ran
        /// and what it did, so the caller decides whether it is worth a line.
        func closeTurn() -> (TimeInterval, [Counter: [String: Int]]) {
            let now = CFAbsoluteTimeGetCurrent()
            lock.lock()
            defer { lock.unlock() }
            let elapsed = now - turnStart
            let snapshot = counts
            turnStart = now
            counts.removeAll(keepingCapacity: true)
            reportedStalling = false
            return (elapsed, snapshot)
        }

        /// The watchdog's read: how long the *open* turn has run, and its
        /// counters — but only the first time it crosses the threshold, so a
        /// long stall is one line rather than one every 500ms.
        func stallingTurn(over threshold: TimeInterval)
            -> (TimeInterval, [Counter: [String: Int]])? {
            lock.lock()
            defer { lock.unlock() }
            let elapsed = CFAbsoluteTimeGetCurrent() - turnStart
            guard elapsed >= threshold, !reportedStalling else { return nil }
            reportedStalling = true
            return (elapsed, counts)
        }

        func install(observer: CFRunLoopObserver, watchdog: DispatchSourceTimer) {
            lock.lock()
            self.observer = observer
            self.watchdog = watchdog
            lock.unlock()
        }

        var isInstalled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return observer != nil
        }
    }

    private static let state = State()

    /// Which layer a repeat is being counted in. Three, because a re-run can
    /// hide in any of them and they don't imply each other.
    enum Counter: String, CaseIterable {
        /// A SwiftUI view body ran.
        case bodies
        /// An `onGeometryChange` action fired — a measurement written back into
        /// state, which is the shape a feedback edge has.
        case geo
        /// Text was laid out to be measured, which happens with no body
        /// evaluation at all.
        case measure
    }

    static func count(_ counter: Counter, _ name: String) {
        guard isOn else { return }
        state.bump(counter, name)
    }

    /// Shorthand for the commonest case, a view body.
    static func body(_ name: String) { count(.bodies, name) }

    /// Installs the run-loop observer and the watchdog. Called once from
    /// `AppDelegate`.
    @MainActor static func start() {
        guard isOn, !state.isInstalled else { return }
        // `.beforeWaiting` fires when the loop is about to sleep, so the span
        // between two of them is one whole turn — including the SwiftUI flush
        // observer that does the layout. Ordered last so the flush is inside the
        // span rather than after it.
        let made = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, true, .max
        ) { _, _ in endTurn() }
        guard let created = made else { return }
        CFRunLoopAddObserver(CFRunLoopGetMain(), created, .commonModes)
        state.install(observer: created, watchdog: makeWatchdog())
        append("--- probe started, pid \(ProcessInfo.processInfo.processIdentifier)")
    }

    /// Reports a turn that is *still running*, from another thread.
    ///
    /// Without this the log says nothing about the freezes that matter most:
    /// the line is written when a turn **ends**, so a freeze the user gets bored
    /// of and force-quits leaves no trace at all. It fires once per turn, so a
    /// long stall is one `stalling` line and then the `stall` line that closes
    /// it — or no closing line, which is itself the finding.
    private static func makeWatchdog() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "insert.layoutProbe", qos: .utility)
        )
        timer.schedule(deadline: .now() + watchdogThreshold, repeating: .milliseconds(500))
        timer.setEventHandler {
            guard let (elapsed, snapshot) = state.stallingTurn(over: watchdogThreshold)
            else { return }
            append(line("stalling", elapsed: elapsed, counts: snapshot))
        }
        timer.resume()
        return timer
    }

    private static func endTurn() {
        let (elapsed, snapshot) = state.closeTurn()
        guard elapsed >= stallThreshold else { return }
        append(line("stall", elapsed: elapsed, counts: snapshot))
    }

    private static func line(
        _ kind: String, elapsed: TimeInterval, counts: [Counter: [String: Int]]
    ) -> String {
        // Uptime is on every line because 34 records cannot explain a 1.1GB
        // footprint, so *something* accumulates — and if per-transaction cost
        // grows with uptime, that is a different bug wearing this one's clothes.
        let parts = Counter.allCases.compactMap { counter -> String? in
            guard let bucket = counts[counter], !bucket.isEmpty else { return nil }
            let inner = bucket.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ",")
            return "\(counter.rawValue)=\(inner)"
        }
        return String(
            format: "%@ %-8@ %6.0fms up=%.0fm %@",
            stamp(), kind, elapsed * 1000, Date().timeIntervalSince(launched) / 60,
            parts.isEmpty ? "(no counters)" : parts.joined(separator: " ")
        )
    }

    private static func stamp() -> String {
        // A formatter per line is fine here: this runs only on a stall, in a
        // build deliberately switched into measuring. It is exactly the
        // allocation `DateCoding` forbids on the *hot* path, and this is the
        // cold one.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    private static func append(_ text: String) {
        guard let data = (text + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }
}
