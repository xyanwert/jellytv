import SwiftUI
import AVFoundation
import UIKit

/// Raw playback surface — no AVKit chrome, no system controls, just the
/// video pixels on a black background. SwiftUI's `VideoPlayer` wraps
/// `AVPlayerViewController`, which always ships some chrome and can't opt
/// out cleanly; this hosts `AVPlayerLayer` directly inside a `UIView`
/// instead, wrapped in a `UIViewRepresentable`.
///
/// `videoGravity = .resizeAspect` letterboxes to fit and never crops.
/// Ported near-verbatim from `/Users/xyan/code/jelly-tv-ios` — pure
/// framework plumbing, no behavior to trim.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PlayerHostView, context: Context) {
        // Re-bind only if the host changed instances — avoids stomping the
        // layer's playhead on every SwiftUI redraw.
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

/// UIView whose backing CALayer IS the `AVPlayerLayer` — `layerClass` (vs a
/// sublayer) lets UIKit's layout pass handle frame propagation automatically.
final class PlayerHostView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
