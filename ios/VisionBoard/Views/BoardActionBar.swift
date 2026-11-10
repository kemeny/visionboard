import SwiftUI

// A floating bar at the bottom of the board, where a thumb reaches it. With a
// clipping selected it holds that clipping's actions, so nothing needs a long
// press to find. With nothing selected it holds Undo, Redo and Fit Board.
struct BoardActionBar: View {
    @Environment(BoardStore.self) private var store
    @Binding var selection: String?
    var onEditText: (String) -> Void
    var onShowStyle: () -> Void
    var onFit: () -> Void

    @State private var deletes = 0
    @AppStorage("board-gesture-tip-seen") private var tipSeen = false

    var body: some View {
        VStack(spacing: 8) {
            if let item = store.item(selection), !tipSeen, !item.isLocked {
                tip
            }
            HStack(spacing: 2) {
                if let item = store.item(selection) {
                    itemButtons(item)
                } else {
                    boardButtons
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(BarButtonStyle())
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .modifier(BarBackground())
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.25), value: selection)
        .sensoryFeedback(.impact(weight: .medium), trigger: deletes)
        // The tip shows the first time a clipping is picked; it goes once that clipping is let go
        .onChange(of: selection) { old, _ in
            if old != nil { tipSeen = true }
        }
    }

    private var tip: some View {
        Label("Pinch to resize, twist to rotate", systemImage: "hand.pinch")
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .modifier(BarBackground())
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .onTapGesture { tipSeen = true }
    }

    @ViewBuilder
    private func itemButtons(_ item: BoardItem) -> some View {
        if item.isLocked {
            Button("Unlock", systemImage: "lock.open") {
                store.update(item.id) { $0.locked = nil }
            }
            .labelStyle(.titleAndIcon)
        } else {
            if item.type == .text {
                Button("Edit Text", systemImage: "character.cursor.ibeam") { onEditText(item.id) }
            }
            Button("Style", systemImage: "paintbrush") { onShowStyle() }
        }
        Button(item.isLiked ? String(localized: "Unlike") : String(localized: "Like"), systemImage: item.isLiked ? "heart.fill" : "heart") {
            store.toggleLike(item.id)
        }
        .foregroundStyle(item.isLiked ? Color.pink : Color.primary)
        .sensoryFeedback(.impact(weight: .light), trigger: item.isLiked)
        if !item.isLocked {
            Button("Duplicate", systemImage: "plus.square.on.square") {
                withAnimation(.snappy) { selection = store.duplicate(item.id)?.id }
            }
        }
        Menu {
            if item.type == .text && !item.isLocked {
                Button("Random Style", systemImage: "dice") {
                    withAnimation(.snappy) { store.update(item.id) { $0.applyRandomLook() } }
                }
            }
            Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") { store.bringToFront(item.id) }
            Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") { store.sendToBack(item.id) }
            if !item.isLocked {
                Button("Lock", systemImage: "lock") { store.update(item.id) { $0.locked = true } }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .font(.body.weight(.medium))
                .frame(minWidth: 48, minHeight: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        Button("Delete", systemImage: "trash", role: .destructive) {
            deletes += 1
            withAnimation(.snappy) {
                selection = nil
                store.delete(item.id)
            }
        }
        .foregroundStyle(.red)
    }

    @ViewBuilder
    private var boardButtons: some View {
        Button("Undo", systemImage: "arrow.uturn.backward") { withAnimation(.snappy) { store.undo() } }
            .disabled(!store.canUndo)
        Button("Redo", systemImage: "arrow.uturn.forward") { withAnimation(.snappy) { store.redo() } }
            .disabled(!store.canRedo)
        Button("Fit Board", systemImage: "arrow.up.left.and.arrow.down.right", action: onFit)
    }
}

// 44 point targets, as the HIG asks for, with a soft press state
private struct BarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.3)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// Liquid Glass where the system has it, a material capsule before that
private struct BarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }
}
