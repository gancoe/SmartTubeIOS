#if os(tvOS) && canImport(Libmpv)

import SwiftUI
import UIKit

struct MPVVideoSurface: UIViewControllerRepresentable {
    let session: MPVPlaybackSession

    func makeUIViewController(context: Context) -> MPVVideoSurfaceViewController {
        MPVVideoSurfaceViewController(session: session)
    }

    func updateUIViewController(_ viewController: MPVVideoSurfaceViewController, context: Context) {
        viewController.updateLayerLayout()
    }

    static func dismantleUIViewController(_ viewController: MPVVideoSurfaceViewController, coordinator: ()) {
        viewController.stop()
    }
}

@MainActor
final class MPVVideoSurfaceViewController: UIViewController {
    private let session: MPVPlaybackSession
    private let metalLayer = MPVVideoMetalLayer()

    init(session: MPVPlaybackSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.addSublayer(metalLayer)
        updateLayerLayout()
        session.attach(to: metalLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayerLayout()
    }

    func updateLayerLayout() {
        metalLayer.frame = view.bounds
        let scale = view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
        metalLayer.contentsScale = scale
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        if size.width > 1, size.height > 1 {
            metalLayer.drawableSize = size
        }
    }

    func stop() {
        session.stop()
    }
}

private final class MPVVideoMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            guard newValue.width > 1, newValue.height > 1 else { return }
            super.drawableSize = newValue
        }
    }
}

#endif
