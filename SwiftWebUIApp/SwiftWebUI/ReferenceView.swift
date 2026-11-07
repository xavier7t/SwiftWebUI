import SwiftUI
import SwiftWebUICore

/// What SwiftWebUI supports, generated from the registry the parser uses.
struct ReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Supported Views & Modifiers").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding([.top, .horizontal], 16)
            TextField("Filter", text: $query).textFieldStyle(.roundedBorder).padding(16)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Reference.sections, id: \.title) { section in
                        let entries = section.entries.filter(matches)
                        if !entries.isEmpty {
                            Text(section.title).font(.headline)
                            ForEach(entries) { entry in EntryView(entry: entry) }
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
    var body: some View {
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
    }
}
