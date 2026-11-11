import UIKit

/// Hooks for the animation frame oracle (M4). They are not part of the public API: only the
/// Example app's dump runner imports this SPI to freeze the document timeline at known times.
@_spi(SVGRenderKitTesting)
public extension SVGView {
    /// The host time the current document's animation timeline started (`beginTime` epoch).
    var animationTimelineEpoch: CFTimeInterval {
        animationEpoch
    }

    /// Calls `handler` on the main thread once the current document is installed and its
    /// animations are attached (a static document calls it on install).
    func onDocumentReadyForFrameOracle(_ handler: @escaping () -> Void) {
        onDocumentReady = handler
    }
}
