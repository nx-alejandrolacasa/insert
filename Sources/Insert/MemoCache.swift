import Foundation

/// A tiny locked memo for values that are expensive to derive and immutable once
/// made — resolved fonts, parsed Markdown blocks, formatted labels. These are
/// derived on the render path, so deriving them once per distinct input instead
/// of once per render is what several hot paths lean on.
///
/// A lock rather than actor isolation because the callers are synchronous view
/// code (the `Collected` / `DebounceState` shape). `@unchecked Sendable` carries
/// two obligations on the caller: `Value` must be immutable (an `NSFont` is; a
/// mutable reference type is not), and `make` must be pure for its key — the same
/// key must always be answerable with the first value made for it.
///
/// Overflow empties the whole store rather than evicting by recency: the caches
/// this backs hold at most a few hundred small entries, and refilling one is
/// exactly the work it was saving — rare is fine, bookkeeping per hit is not.
final class MemoCache<Key: Hashable, Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [Key: Value] = [:]
    private let limit: Int

    init(limit: Int = 256) {
        self.limit = limit
    }

    func value(for key: Key, make: () -> Value) -> Value {
        lock.lock()
        if let hit = store[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        // Made outside the lock: `make` can be slow (a descriptor match, a full
        // parse) and holding the lock across it would serialise every caller. Two
        // threads racing the same key both make it and store the same answer,
        // which the purity rule above makes harmless.
        let made = make()
        lock.lock()
        if store.count >= limit { store.removeAll(keepingCapacity: true) }
        store[key] = made
        lock.unlock()
        return made
    }
}
