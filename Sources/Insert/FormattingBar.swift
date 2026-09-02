import AppKit
import SwiftUI

/// What the editor can do to a selection — the eight buttons on the bar, and
/// the five of them that also have a key.
enum FormattingAction: CaseIterable {
    case bold, italic, underline, strikethrough
    case bulletList, numberedList
    case link, code

    /// The bar's groups, drawn with a hairline between them.
    static let groups: [[FormattingAction]] = [
        [.bold, .italic, .underline, .strikethrough],
        [.bulletList, .numberedList],
        [.link, .code],
    ]

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .link: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        case .bulletList: "Bulleted list"
        case .numberedList: "Numbered list"
        case .link: "Link"
        case .code: "Inline code"
        }
    }

    /// The key that does the same, for the tooltip. The two list actions and
    /// inline code have none — the bar is their only route.
    var shortcut: String? {
        switch self {
        case .bold: "⌘B"
        case .italic: "⌘I"
        case .underline: "⌘U"
        case .strikethrough: "⇧⌘X"
        case .link: "⌘K"
        case .bulletList, .numberedList, .code: nil
        }
    }
}

/// The small bar that floats over a selection in a Markdown body: the
/// formatting shortcuts as buttons, for the selection made with the mouse — the
/// moment a shortcut is furthest from the hand.
///
/// Built like the `@project` dropdown, the app's other transient floating
/// control: glass over the card (or the theme's opaque page under Reduce
/// Transparency), a hairline, no shadow. Its buttons are lone glyphs and keep
/// a soft radius rather than a pill, for the reason the toolbar's do — a glyph
/// rounded into a pill reads as a switch. Hover and press are the washes
/// `FlatButtonStyle` uses, without its fill: eight chips in a row would be
/// louder than the words under them.
///
/// The edit itself is made by the text view (`MarkdownTextView.perform`), so it
/// gets the same undo and caret placement as the key would. `FormattingBarPanel`
/// below is what puts it on screen.
struct FormattingBar: View {
    var perform: (FormattingAction) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Air between the bar's bottom edge and the selected line's top.
    static let gap: CGFloat = 6

    /// A comfortable target — larger than the toolbar's 28pt glyph buttons,
    /// since this one is reached for mid-sentence with a text cursor.
    private static let buttonSide: CGFloat = 32
    private static let inset: CGFloat = 4

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(FormattingAction.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Rectangle()
                        .fill(Stone.line)
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 4)
                }
                ForEach(group, id: \.self) { action in
                    Button { perform(action) } label: {
                        Image(systemName: action.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: Self.buttonSide, height: Self.buttonSide)
                    }
                    .buttonStyle(FormattingBarButtonStyle())
                    .help(action.shortcut.map { "\(action.title) (\($0))" } ?? action.title)
                    .accessibilityLabel(action.title)
                }
            }
        }
        .padding(Self.inset)
        .background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            if reduceTransparency || settings.appReduceTransparency {
                shape.fill(settings.theme.windowFill)
            } else {
                Color.clear.glassEffect(.regular, in: shape)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Stone.line, lineWidth: 0.5)
        }
    }
}

/// A lone glyph with the flat buttons' hover and press washes and nothing
/// else — no fill of its own, no hairline.
private struct FormattingBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration)
    }

    private struct Surface: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            configuration.label
                .foregroundStyle(.primary)
                .background { shape.fill(.primary.opacity(wash)) }
                .contentShape(shape)
                .animation(.easeInOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }

        private var wash: Double {
            if configuration.isPressed { return 0.14 }
            return hovering ? 0.07 : 0
        }
    }
}

// MARK: - The window it floats in

/// The bar's window: one borderless, non-activating panel for the whole app,
/// attached to the editor's window as a child and shown over whichever
/// `MarkdownTextView` last published a selection.
///
/// A window rather than an overlay in the card, and it has to be. The bar was
/// first an `.overlay` of the editor and came up **under the card's title**: the
/// title is a `TextField`, which is an `NSTextField`, and a platform view is
/// drawn above everything SwiftUI paints in the same hosting view, so no
/// `zIndex` reaches it. Being its own window also takes it out of the column's
/// scroll clipping, which an overlay above the first line would have hit at the
/// top of the column.
///
/// Three things keep the click from disturbing the editor. The panel is
/// `.nonactivatingPanel` and can't become key, so the editor's window stays key
/// and the text view stays first responder with its selection lit; the hosting
/// view refuses first responder and says it doesn't need the panel to become key
/// (`needsPanelToBecomeKey`, which `becomesKeyOnlyIfNeeded` consults); and the
/// action still goes through `MarkdownTextView.perform`, which takes the keyboard
/// back if anything did move it. The panel shows the **arrow** cursor over its
/// whole surface — a bar of buttons is not text, and the editor's I-beam ending
/// at the panel's edge is what the window boundary buys.
@MainActor
final class FormattingBarPanel {
    static let shared = FormattingBarPanel()

    private let panel: NSPanel
    private let host: HostingView
    private weak var editor: MarkdownTextView?

    private init() {
        host = HostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = [.intrinsicContentSize]
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The window is shadowless everywhere, and a child window is no exception.
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none
        panel.contentView = host
    }

    /// Places the bar over `editor`'s selection, or hides it when there is none
    /// to place it over — including a selection scrolled out of the column.
    func update(for editor: MarkdownTextView) {
        guard let window = editor.window,
              let anchor = editor.selectionAnchor,
              editor.visibleRect.intersects(anchor)
        else { return hide(for: editor) }

        if self.editor !== editor {
            self.editor = editor
            host.rootView = AnyView(
                FormattingBar { [weak editor] in editor?.perform($0) }
                    .environment(SettingsStore.shared)
            )
        }

        let size = host.fittingSize
        let editorOnScreen = window.convertToScreen(editor.convert(editor.bounds, to: nil))
        let lineOnScreen = window.convertToScreen(editor.convert(anchor, to: nil))
        // Left edge on the selection's, held inside the editor; bottom edge a
        // gap above the selected line (screen y grows upward, so that is `maxY`).
        let x = max(editorOnScreen.minX, min(lineOnScreen.minX, editorOnScreen.maxX - size.width))
        let frame = NSRect(x: x, y: lineOnScreen.maxY + FormattingBar.gap,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true)

        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    /// Hides the bar if it is `editor`'s. Another editor's bar is left alone,
    /// since a resigning editor and the one taking over both report in.
    func hide(for editor: MarkdownTextView) {
        guard self.editor === editor || self.editor == nil else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.editor = nil
    }

    private final class HostingView: NSHostingView<AnyView> {
        override var acceptsFirstResponder: Bool { false }
        override var needsPanelToBecomeKey: Bool { false }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
        }
    }
}
