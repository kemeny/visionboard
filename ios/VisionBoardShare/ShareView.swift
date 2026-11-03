import SwiftUI

struct ShareView: View {
    @Bindable var model: ShareModel
    @FocusState private var captionFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add to Board")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { model.cancel() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add", systemImage: "checkmark") { model.add() }
                            .disabled(!model.canAdd)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Getting it ready…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Can't Add This", systemImage: "exclamationmark.triangle", description: Text(message))
        case .ready, .saving:
            Form {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(model.things) { thing in
                                ThingPreview(thing: thing)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } footer: {
                    if model.things.contains(where: \.isVideo) {
                        Text("Videos go on the board as a still from the clip.")
                    }
                }
                if model.boards.count > 1 {
                    Section {
                        Picker("Board", selection: $model.board) {
                            ForEach(model.boards) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                Section {
                    TextField("Add a goal to go with it", text: $model.caption, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($captionFocused)
                } footer: {
                    Text("It shows up on your board the next time you open VisionBoard.")
                }
            }
            .disabled({ if case .saving = model.phase { true } else { false } }())
        }
    }
}

private struct ThingPreview: View {
    let thing: ShareModel.Thing

    var body: some View {
        Group {
            if let image = thing.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 160)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        if thing.isVideo {
                            Image(systemName: "video.fill")
                                .font(.caption)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(6)
                        }
                    }
            } else if let text = thing.text {
                Text(text)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(width: 160, height: 160, alignment: .topLeading)
                    .background(.fill.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(thing.image != nil ? (thing.isVideo ? "Video still" : "Photo") : (thing.text ?? ""))
    }
}
