import PhotosUI
import SwiftUI

struct BoardView: View {
    @Environment(BoardStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(AppRouter.self) private var router

    @State private var selection: String?
    @State private var showStyle = false
    @State private var editingTextID: String?
    @State private var showPhotoPicker = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var camera = CanvasCamera()
    @State private var viewport: CGSize = .zero
    @State private var pendingTemplate: BoardTemplate?
    @State private var importError: String?
    @AppStorage("canvas-pattern") private var pattern: CanvasPattern = .dots
    @AppStorage("canvas-paper") private var paper: PaperColor = .moleskine

    var body: some View {
        NavigationStack {
            BoardCanvas(
                selection: $selection,
                camera: $camera,
                viewport: $viewport,
                pattern: pattern,
                paper: paper,
                onEditText: { editingTextID = $0 },
                onShowStyle: { showStyle = true }
            )
            .ignoresSafeArea(edges: .bottom)
            .overlay {
                if store.items.isEmpty { emptyState }
            }
            .navigationTitle("Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .boardOverflowMenu { overflowMenu }
            .prefersToolbarItemsWhenCompressed()
            .inspector(isPresented: $showStyle) {
                ItemInspector(itemID: selection, onEditText: { editingTextID = $0 }, onDone: { showStyle = false })
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                    .presentationDetents([.medium, .large])
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhotos, maxSelectionCount: 10, matching: .images)
            .onChange(of: pickedPhotos) { _, items in
                guard !items.isEmpty else { return }
                pickedPhotos = []
                Task { await importPhotos(items) }
            }
            .onChange(of: selection) { _, id in
                if id == nil { showStyle = false }
            }
            .sheet(item: Binding(
                get: { editingTextID.map(EditTarget.init) },
                set: { editingTextID = $0?.id }
            )) { target in
                TextEditSheet(itemID: target.id)
            }
            .confirmationDialog(
                "Replace your board with \(pendingTemplate?.name ?? "this template")?",
                isPresented: Binding(get: { pendingTemplate != nil }, set: { if !$0 { pendingTemplate = nil } }),
                titleVisibility: .visible
            ) {
                Button("Replace Board", role: .destructive) {
                    if let template = pendingTemplate { apply(template) }
                }
            } message: {
                Text("Everything on your current board will be removed.")
            }
            .alert("Couldn't Add Photo", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // HIG order for side bars on iPhone Duo: navigation first, then the
    // prominent action. Every item has a title and a symbol so the system can
    // show either one, or move it into the overflow menu.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                router.tab = .settings
            } label: {
                Label(syncLabel, systemImage: syncSymbol)
            }
            .accessibilityHint("Opens sync settings")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            addMenu
            if selection != nil {
                Button("Style", systemImage: "paintbrush") { showStyle.toggle() }
            }
            Button("Fit Board", systemImage: "arrow.up.left.and.arrow.down.right") {
                withAnimation(.snappy) { camera = .fitting(store.items, in: viewport) }
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Photo", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
            Button("Goal", systemImage: "textformat") { addText() }
            Menu {
                templateButtons
            } label: {
                Label("Template", systemImage: "square.grid.2x2")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
    }

    @ViewBuilder
    private var overflowMenu: some View {
        Picker(selection: $pattern) {
            ForEach(CanvasPattern.allCases) { Text($0.label).tag($0) }
        } label: {
            Label("Pattern", systemImage: "circle.grid.3x3")
        }
        .pickerStyle(.menu)
        Picker(selection: $paper) {
            ForEach(PaperColor.allCases) { Text($0.label).tag($0) }
        } label: {
            Label("Paper", systemImage: "doc")
        }
        .pickerStyle(.menu)
        if sync.isOn {
            Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") { Task { await sync.syncNow() } }
        }
    }

    @ViewBuilder
    private var templateButtons: some View {
        ForEach(BoardTemplate.all) { template in
            Button(template.name, systemImage: template.symbol) {
                if store.items.isEmpty { apply(template) } else { pendingTemplate = template }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Start Your Board", systemImage: "square.on.square.dashed")
        } description: {
            Text("Add the photos and goals that pull you forward. You'll see one each day.")
        } actions: {
            Button("Add Photos", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
                .buttonStyle(.borderedProminent)
            Button("Add a Goal", systemImage: "textformat") { addText() }
            Menu {
                templateButtons
            } label: {
                Label("Start from a Template", systemImage: "square.grid.2x2")
            }
        }
    }

    private var syncLabel: String {
        switch sync.status {
        case .unavailable, .off: "Not Synced"
        case .syncing: "Syncing"
        case .synced: "Synced"
        case .error: "Sync Problem"
        }
    }

    private var syncSymbol: String {
        switch sync.status {
        case .unavailable, .off: "icloud.slash"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud"
        case .error: "exclamationmark.icloud"
        }
    }

    private var visibleCenter: CGPoint {
        camera.toCanvas(CGPoint(x: viewport.width / 2, y: viewport.height / 2))
    }

    private func addText() {
        let item = store.addText(at: visibleCenter)
        selection = item.id
        editingTextID = item.id
    }

    private func importPhotos(_ picked: [PhotosPickerItem]) async {
        var center = visibleCenter
        for photo in picked {
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else { continue }
                let imported = try await ImageStore.shared.importPhoto(data)
                let item = store.addImage(content: imported.content, aspect: imported.aspect, at: center)
                selection = item.id
                center.x += 30
                center.y += 30
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func apply(_ template: BoardTemplate) {
        guard let file = template.load() else { return }
        store.replaceBoard(with: file)
        selection = nil
        pendingTemplate = nil
        withAnimation(.snappy) { camera = .fitting(file.items, in: viewport) }
    }
}

private struct EditTarget: Identifiable {
    let id: String
}

struct TextEditSheet: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextField("Your goal", text: $text, axis: .vertical)
                .font(.title2)
                .lineLimit(3...8)
                .focused($focused)
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle("Edit Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") {
                            store.update(itemID) { $0.content = text }
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            let current = store.item(itemID)?.content ?? ""
            text = current == placeholderText ? "" : current
            focused = true
        }
    }
}
