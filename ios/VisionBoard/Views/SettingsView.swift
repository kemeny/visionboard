import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

struct SettingsView: View {
    @Environment(BoardStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(Reminders.self) private var reminders
    @Environment(AppRouter.self) private var router

    @State private var keyInput = ""
    @State private var joining = false
    @State private var joinError: String?
    @State private var showScanner = false
    @State private var confirmDelete = false
    @State private var confirmJoin = false
    @State private var reminderTime = Date()
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("canvas-paper") private var paper: PaperColor = .moleskine

    var body: some View {
        NavigationStack {
            Form {
                syncSection
                remindersSection
                Section {
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                    Picker(selection: $paper) {
                        ForEach(PaperColor.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label("Board Paper", systemImage: "doc")
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("The board paper and the words written on it switch between day and night versions with the appearance.")
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    if let site = URL(string: "https://kemenystudio.com") {
                        Link(destination: site) {
                            Label("Made by Kemeny Studio", systemImage: "safari")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showScanner) {
                ScannerSheet { payload in
                    showScanner = false
                    keyInput = payload
                    confirmJoin = true
                }
            }
            .confirmationDialog("Open the synced board on this iPhone?", isPresented: $confirmJoin, titleVisibility: .visible) {
                Button("Replace This Board") { Task { await join(keyInput) } }
            } message: {
                Text("The board from your other device replaces the one on this iPhone.")
            }
            .confirmationDialog("Delete the cloud copy?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete from Cloud", role: .destructive) {
                    Task { try? await sync.deleteCloudCopy() }
                }
            } message: {
                Text("Your board stays on this iPhone, but every other device stops syncing and its photos are removed from the cloud.")
            }
            .onAppear { takeIncomingKey() }
            .onChange(of: router.incomingSyncKey) { takeIncomingKey() }
        }
    }

    // MARK: Sync

    @ViewBuilder
    private var syncSection: some View {
        if sync.status == .unavailable {
            Section("Sync") {
                Label("Sync isn't set up in this build.", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
            }
        } else if let key = sync.key {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        if sync.status == .syncing { ProgressView() }
                        Text(statusText)
                    }
                }
                if let error = sync.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                if let link = SyncAPI.shareLink(for: key) {
                    QRCodeView(text: link.absoluteString)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .accessibilityLabel("QR code for your sync link")
                    ShareLink(item: link) {
                        Label("Share Sync Link", systemImage: "square.and.arrow.up")
                    }
                }
                LabeledContent("Sync Key") {
                    Text(key)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") { Task { await sync.syncNow() } }
            } header: {
                Text("Sync")
            } footer: {
                Text("Scan the code with your other phone's camera, or open the link on a computer, to use the same board there. Anyone with the key can see and edit this board.")
            }
            Section {
                Button("Stop Syncing on This iPhone", systemImage: "icloud.slash") { sync.disconnect() }
                Button("Delete Cloud Copy", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        } else {
            Section {
                Button("Turn On Sync", systemImage: "icloud") { Task { await sync.enable() } }
            } header: {
                Text("Sync")
            } footer: {
                Text("Keep this board in step with VisionBoard on the web and your other devices.")
            }
            Section {
                if DataScannerViewController.isSupported {
                    Button("Scan QR Code", systemImage: "qrcode.viewfinder") { showScanner = true }
                }
                TextField("Paste a sync key or link", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button("Open Synced Board", systemImage: "arrow.down.circle") { confirmJoin = true }
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty || joining)
                if let joinError {
                    Label(joinError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            } header: {
                Text("Already Syncing Elsewhere?")
            } footer: {
                Text("On the web, open the cloud menu and show the QR code.")
            }
        }
    }

    private var statusText: String {
        switch sync.status {
        case .syncing: "Syncing…"
        case .synced: "Up to date"
        case .error: "Couldn't sync"
        case .off, .unavailable: "Off"
        }
    }

    private func join(_ input: String) async {
        joining = true
        defer { joining = false }
        do {
            try await sync.connect(input)
            keyInput = ""
            joinError = nil
            router.tab = .board
        } catch {
            joinError = error.localizedDescription
        }
    }

    private func takeIncomingKey() {
        guard let key = router.incomingSyncKey else { return }
        router.incomingSyncKey = nil
        if sync.key == key { return }
        keyInput = key
        confirmJoin = true
    }

    // MARK: Reminders

    private var remindersSection: some View {
        Section {
            Toggle("Daily Reminder", systemImage: "bell", isOn: Binding(
                get: { reminders.isEnabled },
                set: { on in
                    if on {
                        Task { await reminders.enable(hour: reminders.hour, items: store.items) }
                    } else {
                        reminders.disable()
                    }
                }
            ))
            if reminders.isEnabled {
                DatePicker("Time", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: reminders.hour, minute: 0, second: 0, of: .now) ?? .now },
                    set: { date in
                        let hour = Calendar.current.component(.hour, from: date)
                        Task { await reminders.enable(hour: hour, items: store.items) }
                    }
                ), displayedComponents: .hourAndMinute)
                Button("Send a Test", systemImage: "paperplane") { Task { await reminders.sendTest(items: store.items) } }
                if let message = reminders.testMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }
            if let error = reminders.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Each day at this hour you'll get one goal and one photo from your board. Reminders go out on the hour.")
        }
    }
}

struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}

// Reads the QR code the web app shows for its sync link
private struct ScannerSheet: View {
    var onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRScanner(onScan: onScan)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Scan Sync Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { dismiss() }
                    }
                }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning { try? controller.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var done = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let payload = code.payloadStringValue, payload.contains("sync=") || payload.count >= 20 {
                    done = true
                    dataScanner.stopScanning()
                    onScan(payload)
                    return
                }
            }
        }
    }
}
