import AppKit
import ApplicationServices
import CoreGraphics

final class MenuExtraIconProvider {
    private var cache = [String: NSImage]()
    private let maxCacheCount = 160

    func icon(
        for element: AXUIElement,
        owner: NSRunningApplication,
        frame: CGRect?,
        title: String,
        index: Int
    ) -> NSImage? {
        let key = "\(owner.processIdentifier):\(index):\(title):\(frame?.debugDescription ?? "no-frame")"
        if let cached = cache[key] {
            return cached
        }

        let image = captureIcon(frame: frame) ?? renderOnMain {
            owner.icon?.menuSizedCopy()
        }
        if let image {
            cache[key] = image
            trimCacheIfNeeded()
        }
        return image
    }

    private func captureIcon(frame: CGRect?) -> NSImage? {
        guard let frame,
              frame.width > 2,
              frame.height > 2,
              CGPreflightScreenCaptureAccess()
        else {
            return nil
        }

        let imageOptions: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let image = CGWindowListCreateImage(
            frame,
            .optionOnScreenOnly,
            CGWindowID(0),
            imageOptions
        ), !image.isProbablyBlank
        else {
            return nil
        }

        return renderOnMain {
            NSImage(cgImage: image, size: frame.size).menuSizedCopy()
        }
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

private extension CGImage {
    var isProbablyBlank: Bool {
        guard let providerData = dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData)
        else {
            return false
        }

        let length = CFDataGetLength(providerData)
        guard length > 0 else {
            return true
        }

        let sampleCount = min(length, 4096)
        var nonZeroCount = 0
        for offset in stride(from: 0, to: sampleCount, by: 4) {
            let upperBound = min(offset + 4, sampleCount)
            for byteIndex in offset ..< upperBound where bytes[byteIndex] != 0 {
                nonZeroCount += 1
                if nonZeroCount > 8 {
                    return false
                }
            }
        }
        return true
    }
}

private extension NSImage {
    func menuSizedCopy() -> NSImage {
        let targetSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let sourceAspect = size.width / max(size.height, 1)
        let targetAspect = targetSize.width / targetSize.height
        let drawSize: NSSize

        if sourceAspect > targetAspect {
            drawSize = NSSize(width: targetSize.width, height: targetSize.width / sourceAspect)
        } else {
            drawSize = NSSize(width: targetSize.height * sourceAspect, height: targetSize.height)
        }

        let rect = NSRect(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        image.isTemplate = isTemplate
        return image
    }
}
