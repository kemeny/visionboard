import SwiftUI

// Styling for the selected clipping. A trailing column on wide screens like
// iPhone Duo's inner display, a sheet on the outer display and other iPhones.
struct ItemInspector: View {
    @Environment(BoardStore.self) private var store
    let itemID: String?
    var onEditText: (String) -> Void
    var onDone: () -> Void
    @State private var shuffles = 0

    var body: some View {
        NavigationStack {
            Group {
                if let item = store.item(itemID) {
                    form(for: item)
                } else {
                    ContentUnavailableView(
                        "Nothing Selected",
                        systemImage: "hand.tap",
                        description: Text("Tap a photo or goal on your board to style it.")
                    )
                }
            }
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", action: onDone)
                }
            }
        }
    }

    @ViewBuilder
    private func form(for item: BoardItem) -> some View {
        Form {
            if item.type == .text {
                Section("Text") {
                    Button("Random Style", systemImage: "dice") {
                        withAnimation(.snappy) { store.update(item.id) { $0.applyRandomLook() } }
                        shuffles += 1
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: shuffles)
                    Button("Edit Text", systemImage: "character.cursor.ibeam") { onEditText(item.id) }
                    Picker("Font", selection: binding(item, \.fontStyle, default: TextStyle.clean.rawValue)) {
                        ForEach(TextStyle.allCases) { style in
                            Text(style.label)
                                .font(style.font(size: 17))
                                .tag(Optional(style.rawValue))
                        }
                    }
                    Picker("Size", selection: binding(item, \.fontSize, default: 18)) {
                        ForEach(Palette.fontSizes, id: \.self) { size in
                            Text("\(Int(size)) pt").tag(Optional(size))
                        }
                    }
                }
                Section("Text Color") {
                    SwatchGrid(colors: Palette.textColors, selection: binding(item, \.color, default: "#1a1a1a"))
                }
                Section("Background") {
                    SwatchGrid(colors: Palette.backgrounds, selection: binding(item, \.bgColor, default: "transparent"))
                }
            }

            Section("Arrange") {
                LabeledContent("Rotation") {
                    Slider(value: rotation(item), in: -45...45, step: 0.5) {
                        Text("Rotation")
                    } minimumValueLabel: {
                        Image(systemName: "rotate.left")
                    } maximumValueLabel: {
                        Image(systemName: "rotate.right")
                    }
                }
                Toggle("Locked", systemImage: "lock", isOn: Binding(
                    get: { item.isLocked },
                    set: { locked in store.update(item.id) { $0.locked = locked ? true : nil } }
                ))
                Toggle("Liked", systemImage: "heart", isOn: Binding(
                    get: { item.isLiked },
                    set: { _ in store.toggleLike(item.id) }
                ))
                Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") { store.bringToFront(item.id) }
                Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") { store.sendToBack(item.id) }
                Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(item.id) }
            }

            Section {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    store.delete(item.id)
                    onDone()
                }
            }
        }
    }

    private func binding<T: Equatable>(_ item: BoardItem, _ path: WritableKeyPath<BoardItem, T?>, default value: T) -> Binding<T?> {
        Binding(
            get: { store.item(item.id)?[keyPath: path] ?? value },
            set: { newValue in store.update(item.id) { $0[keyPath: path] = newValue } }
        )
    }

    private func rotation(_ item: BoardItem) -> Binding<Double> {
        Binding(
            get: { store.item(item.id)?.rotation ?? 0 },
            set: { degrees in store.update(item.id) { $0.rotation = degrees } }
        )
    }
}

private struct SwatchGrid: View {
    let colors: [String]
    @Binding var selection: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(colors, id: \.self) { css in
                let selected = selection == css
                Button {
                    selection = css
                } label: {
                    ZStack {
                        if let color = Color(css: css) {
                            Circle().fill(color)
                        } else {
                            Circle().fill(.background)
                            Image(systemName: "slash.circle").foregroundStyle(.secondary)
                        }
                        Circle().strokeBorder(.separator, lineWidth: 1)
                        if selected {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 3)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.name(for: css))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private static func name(for css: String) -> String {
        let names = [
            "#1a1a1a": "Ink", "#6b7280": "Gray", "#ef4444": "Red", "#f97316": "Orange", "#eab308": "Yellow",
            "#22c55e": "Green", "#3b82f6": "Blue", "#8b5cf6": "Purple", "#ec4899": "Pink", "#ffffff": "White",
            "transparent": "None", "rgba(255,255,255,0.85)": "White", "rgba(0,0,0,0.75)": "Black",
            "rgba(239,68,68,0.85)": "Red", "rgba(59,130,246,0.85)": "Blue", "rgba(234,179,8,0.85)": "Yellow",
            "rgba(34,197,94,0.85)": "Green", "rgba(139,92,246,0.85)": "Purple", "rgba(236,72,153,0.85)": "Pink",
            "rgba(249,115,22,0.85)": "Orange",
        ]
        return names[css] ?? "Custom color"
    }
}
