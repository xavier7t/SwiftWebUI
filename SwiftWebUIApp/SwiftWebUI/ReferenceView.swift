import SwiftUI
import SwiftWebUICore

/// What SwiftWebUI supports, generated from the registry the parser uses.
struct ReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// Whether a file is open to insert into.
    var canInsert = false
    var fileName: String?
    var insert: (ReferenceEntry) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Supported Views & Modifiers").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding([.top, .horizontal], 16)
            TextField("Filter", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.vertical, 8)
            if !canInsert {
                Text("Open a file to use the + buttons.").font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Reference.sections, id: \.title) { section in
                        let entries = section.entries.filter(matches)
                        if !entries.isEmpty {
                            Text(section.title).font(.headline)
                            ForEach(entries) { entry in EntryView(entry: entry, canInsert: canInsert, fileName: fileName) { insert(entry) } }
                        }
                    }
                    Text("Anything else shows an error with its line, and the last working preview stays on screen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 520, height: 560)
    }

    private func matches(_ e: ReferenceEntry) -> Bool {
        query.isEmpty || e.name.localizedCaseInsensitiveContains(query) || e.summary.localizedCaseInsensitiveContains(query)
    }
}

private struct EntryView: View {
    let entry: ReferenceEntry
    let canInsert: Bool
    let fileName: String?
    let insert: () -> Void
    @State private var added = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            details
            Button {
                insert()
                added = true
                Task { try? await Task.sleep(for: .seconds(1.2)); added = false }
            } label: {
                Image(systemName: added ? "checkmark" : "plus")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .disabled(!canInsert)
            .help(canInsert ? "Insert an example of \(entry.name) into \(fileName ?? "the open file") at the cursor"
                  : "Open a file to insert this example")
            .accessibilityLabel("Insert \(entry.name) example")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.name).font(.body.monospaced().bold())
            Text(entry.summary).foregroundStyle(.secondary)
            Text(entry.example).font(.callout.monospaced())
                .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            let described = entry.arguments.filter { !$0.summary.isEmpty }
            ForEach(Array(described.enumerated()), id: \.offset) { _, a in
                Text("\(a.label ?? "unlabeled"): \(a.summary)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
