import Foundation

/// Watches one or more directories for changes and fires a debounced callback
/// on the main actor. Used to pick up edits made outside the app (Obsidian,
/// Finder, iCloud sync). Dependency-free — plain `DispatchSource` file-system
/// object sources over directory file descriptors.
final class DirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []

    init(urls: [URL], onChange: @escaping @Sendable @MainActor () -> Void) {
        let queue = DispatchQueue(label: "com.alejandrolacasa.insert.watcher")
        let debounce = DebounceState()
        for url in urls {
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend],
                queue: queue
            )
            source.setEventHandler {
                debounce.schedule(on: queue) {
                    Task { @MainActor in onChange() }
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    deinit {
        for source in sources { source.cancel() }
    }
}

/// Coalesces bursts of file-system events. Confined to the watcher's serial
/// queue, so its mutable state is safe despite `@unchecked Sendable`.
private final class DebounceState: @unchecked Sendable {
    private var work: DispatchWorkItem?

    func schedule(on queue: DispatchQueue, _ block: @escaping @Sendable () -> Void) {
        work?.cancel()
        let item = DispatchWorkItem(block: block)
        work = item
        queue.asyncAfter(deadline: .now() + 0.35, execute: item)
    }
}
