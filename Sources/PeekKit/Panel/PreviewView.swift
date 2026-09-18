import AppKit
import SwiftUI

/// Content view of the Dock hover preview panel. Purely a renderer over `PreviewModel`; all
/// state transitions and actions live in `PreviewPanelController`.
struct PreviewView: View {
    @ObservedObject var model: PreviewModel

    private var hiddenCount: Int {
        model.items.filter { $0.state == .peekHidden }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PreviewLayout.spacing) {
            header
            cells
        }
        .padding(PreviewLayout.padding)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let icon = model.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(model.appName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            if hiddenCount > 0 {
                Text("\(hiddenCount) versteckt")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: PreviewLayout.headerHeight)
    }

    @ViewBuilder
    private var cells: some View {
        switch model.edge {
        case .bottom:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PreviewLayout.spacing) {
                    ForEach(model.items) { item in
                        PreviewCell(item: item, appIcon: model.appIcon, thumbnailSize: model.thumbnailSize, model: model)
                    }
                }
            }
        case .left, .right:
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: PreviewLayout.spacing) {
                    ForEach(model.items) { item in
                        PreviewCell(item: item, appIcon: model.appIcon, thumbnailSize: model.thumbnailSize, model: model)
                    }
                }
            }
        }
    }
}

/// SwiftUI's `onHover` is tied to the window's key/active state, and the preview panel never
/// becomes key. An `.activeAlways` tracking area reports hover regardless.
private struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct PreviewCell: View {
    let item: PreviewWindowItem
    let appIcon: NSImage?
    let thumbnailSize: Settings.ThumbnailSize
    let model: PreviewModel

    @State private var hovering = false

    private var thumbnailBox: CGSize {
        CGSize(width: thumbnailSize.width, height: thumbnailSize.height)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                thumbnailView
                if item.state != .visible {
                    stateBadge
                }
            }
            .frame(width: thumbnailBox.width, height: thumbnailBox.height)

            Text(item.displayTitle)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: thumbnailBox.width, height: PreviewLayout.titleHeight, alignment: .center)
        }
        .padding(PreviewLayout.cellInset)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovering ? Color.primary.opacity(0.12) : Color.clear)
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                HStack(spacing: 4) {
                    if item.state == .visible {
                        cellButton(systemName: "eye.slash", help: "Verstecken") {
                            model.onHide?(item)
                        }
                    }
                    cellButton(systemName: "xmark", help: "Schließen") {
                        model.onClose?(item)
                    }
                }
                .padding(4)
            }
        }
        .background(HoverTracker { hovering = $0 })
        .contentShape(Rectangle())
        .onTapGesture {
            model.onSelect?(item)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let cgImage = item.image {
                Image(decorative: cgImage, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.08))
                    .overlay {
                        if let appIcon {
                            Image(nsImage: appIcon)
                                .resizable()
                                .frame(width: 48, height: 48)
                        }
                    }
            }
        }
        .frame(width: thumbnailBox.width, height: thumbnailBox.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(item.state == .visible ? 1 : 0.45)
    }

    private var stateBadge: some View {
        Text(stateLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .padding(4)
    }

    private var stateLabel: String {
        switch item.state {
        case .peekHidden: return "versteckt"
        case .minimized: return "minimiert"
        case .appHidden: return "ausgeblendet"
        case .visible: return ""
        }
    }

    private func cellButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.regularMaterial))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
