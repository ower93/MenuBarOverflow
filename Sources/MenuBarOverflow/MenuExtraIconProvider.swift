import AppKit

final class MenuExtraIconProvider {
    private var cache = [String: NSImage]()
    private let maxCacheCount = 160

    func icon(for owner: NSRunningApplication) -> NSImage? {
        let key = owner.bundleIdentifier ?? "pid:\(owner.processIdentifier)"
        if let cached = cache[key] {
            return cached
        }

        let image = renderOnMain { owner.icon }
        if let image {
            cache[key] = image
            trimCacheIfNeeded()
        }
        return image
    }

    private func trimCacheIfNeeded() {
        guard cache.count > maxCacheCount else {
            return
        }

        for key in cache.keys.prefix(cache.count - maxCacheCount) {
            cache.removeValue(forKey: key)
        }
    }
}

private func renderOnMain<T>(_ work: @escaping () -> T) -> T {
    if Thread.isMainThread {
        return work()
    }
    return DispatchQueue.main.sync(execute: work)
}
