import CoreGraphics
import Foundation

nonisolated struct VirtualDisplayMode: Hashable, Sendable {
    var width: Int
    var height: Int
    var density: Int

    var pixelWidth: Int { width * density }
    var pixelHeight: Int { height * density }

    static let minimumLongSide: CGFloat = 800
    static let minimumShortSide: CGFloat = 525

    static let minimumWindowPoints = CGSize(width: minimumLongSide * 0.75, height: minimumShortSide * 0.75)

    static let resolutionScaleRange: ClosedRange<Double> = 1...5
    static let resolutionScaleStep = 0.25
    /// Quarter steps up to 2×, then coarser (a phone can want a lot more room than it has).
    static let resolutionScales: [Double] = [1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5]
    /// The most pixels on a side asked for (a 6K display's). Past it at two pixels per point the display drops to
    /// one, so a high scale still gives that much more room, just not sharper; past it at one, it stops growing.
    static let maximumPixelSide: CGFloat = 6016
    static let defaultResolutionScale: Double = 1

    init(width: Int, height: Int, density: Int) {
        self.width = width
        self.height = height
        self.density = density
    }

    init?(matching area: CGSize, screenScale: CGFloat, resolutionScale: CGFloat = 1) {
        guard area.width >= 1, area.height >= 1 else { return nil }
        // ScreenSharing's -[SSSessionView setDynamicSize:] requests two pixels per point (ScreenSharing 776.27,
        // macOS 27.0.1 26A434, UUID EC0B2C20-F816-3FCE-822D-F9403C09EB50, -[SSSessionView setDynamicSize:]
        // 0x1cc0a3788..0x1cc0a37f0).
        var density = screenScale >= 2 ? 2 : 1
        var points = CGSize(width: area.width * resolutionScale, height: area.height * resolutionScale)
        if max(points.width, points.height) * CGFloat(density) > Self.maximumPixelSide { density = 1 }
        let largest = max(points.width, points.height) * CGFloat(density)
        if largest > Self.maximumPixelSide {
            let fit = Self.maximumPixelSide / largest
            points = CGSize(width: points.width * fit, height: points.height * fit)
        }
        let grow = max(
            1, Self.minimumLongSide / max(points.width, points.height), Self.minimumShortSide / min(points.width, points.height))
        self.init(
            width: Int((points.width * grow + 0.001).rounded(.down)),
            height: Int((points.height * grow + 0.001).rounded(.down)),
            density: density
        )
    }

    static func largestSide(onScreen screen: CGSize, screenScale: CGFloat) -> Int {
        guard
            let mode = VirtualDisplayMode(
                matching: screen, screenScale: screenScale, resolutionScale: resolutionScaleRange.upperBound)
        else { return 0 }
        return max(mode.pixelWidth, mode.pixelHeight)
    }

    func aligned(toWidthMultiple multiple: Int) -> VirtualDisplayMode {
        var mode = self
        while mode.pixelWidth % multiple != 0 {
            mode.width -= 1
        }
        return mode
    }
}

@MainActor
final class VirtualDisplayRequests {
    private var send: ((VirtualDisplayMode) -> Void)?
    private var widthMultiple = 1
    private var sizedByConnection = false
    private var framebufferSize: CGSize?
    private var sent: VirtualDisplayMode?
    private var awaitsAnswer = false
    private(set) var isOpening = false
    var onIdle: (() -> Void)?

    var isIdle: Bool { !awaitsAnswer && !isOpening }

    func reset(widthMultiple: Int = 1, sizedByConnection: Bool = false, sender: ((VirtualDisplayMode) -> Void)?) {
        send = sender
        self.widthMultiple = widthMultiple
        self.sizedByConnection = sizedByConnection
        framebufferSize = nil
        sent = nil
        awaitsAnswer = false
        isOpening = false
    }

    func open() {
        isOpening = true
    }

    func connectionDidOpen(offersVirtualDisplay: Bool) {
        guard isOpening else { return }
        isOpening = false
        if sizedByConnection, let sent, framebufferSize == CGSize(width: sent.pixelWidth, height: sent.pixelHeight) {
            answered()
        } else if !offersVirtualDisplay {
            stopWaiting()
        } else {
            reportIdle()
        }
    }

    func request(_ requested: VirtualDisplayMode) {
        let mode = requested.aligned(toWidthMultiple: widthMultiple)
        guard mode != sent, let send else { return }
        sent = mode
        awaitsAnswer = true
        send(mode)
    }

    func framebufferDidChange(width: Int, height: Int, resized: Bool) {
        let size = CGSize(width: width, height: height)
        let previous = framebufferSize
        if resized {
            framebufferSize = size
        }
        guard awaitsAnswer, let sent else { return }
        if sent.pixelWidth == width && sent.pixelHeight == height || resized && previous != nil && previous != size {
            answered()
        }
    }

    func displaysDidChange(_ displays: [RemoteDisplay], framebufferWidth: Int, framebufferHeight: Int) {
        guard awaitsAnswer, let sent, sent.pixelWidth == framebufferWidth, sent.pixelHeight == framebufferHeight,
            displays.contains(where: { $0.isVirtual && $0.width == sent.width && $0.height == sent.height })
        else { return }
        answered()
    }

    func stopWaiting() {
        awaitsAnswer = false
        sent = nil
        reportIdle()
    }

    private func answered() {
        awaitsAnswer = false
        reportIdle()
    }

    private func reportIdle() {
        if isIdle { onIdle?() }
    }
}
