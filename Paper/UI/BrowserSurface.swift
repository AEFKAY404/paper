import AppKit
import SwiftUI

struct BrowserSurface: NSViewRepresentable {
    let session: any BrowserSession

    func makeNSView(context: Context) -> BrowserContainerView {
        let container = BrowserContainerView()
        container.show(session.view)
        return container
    }

    func updateNSView(_ nsView: BrowserContainerView, context: Context) {
        nsView.show(session.view)
    }
}

final class BrowserContainerView: NSView {
    private weak var hosted: NSView?
    private var hostedConstraints: [NSLayoutConstraint] = []

    func show(_ view: NSView) {
        guard hosted !== view else { return }
        NSLayoutConstraint.deactivate(hostedConstraints)
        hostedConstraints.removeAll()
        hosted?.removeFromSuperview()
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        hostedConstraints = [
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(hostedConstraints)
        hosted = view
    }
}
