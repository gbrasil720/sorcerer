import SwiftUI

/// What this world knows, and who knows it. Retagging a fact changes what characters
/// can say from the next round on; past rounds stay as they were.
struct ContextScreen: View {
    @Environment(Store.self) private var store
    @State private var writing = false

    var body: some View {
        if let e = store.experiment {
            VStack(spacing: 0) {
                ExperimentBar {
                    if let b = e.brief {
                        Button("save as “\(b.title)” context") { store.saveContext(b) }.buttonStyle(SButton())
                            .help("Reuse this brief in new experiments")
                    }
                }
                HStack(spacing: 0) {
                    ScrollView { brief(e).padding(32).frame(maxWidth: .infinity, alignment: .leading) }
                    Rectangle().fill(Color.line).frame(width: 1)
                    ScrollView { sources(e).padding(24) }.frame(width: 380).background(Color.sidebar)
                }
            }
        }
    }

    @ViewBuilder
    private func brief(_ e: Experiment) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Caps("the brief · what the world knows")
                Spacer()
                if e.brief != nil { Text("click a tag to change who knows it").font(.mono(10)).foregroundStyle(Color.muted) }
            }
            if let b = e.brief {
                Text(b.title).font(.display(30))
                Text(b.tagline).font(.display(14, .regular)).foregroundStyle(Color.paper.opacity(0.8))
                let insiders = store.branch?.characters.filter { $0.insider == true }.map { "@\($0.handle)" } ?? []
                Text(insiders.isEmpty ? "No insiders in this branch: insider facts reach nobody." : "Insiders: \(insiders.joined(separator: ", "))")
                    .font(.mono(10)).foregroundStyle(Color.muted)
                ForEach(b.facts) { f in
                    HStack(alignment: .top, spacing: 14) {
                        Button { retag(f.id) } label: { AudienceTag(audience: f.audience) }.buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(f.text).font(.display(14, .regular))
                                .foregroundStyle(f.audience == .hidden ? Color.muted : Color.paper)
                            if !f.source.isEmpty { Text("↳ \(f.source)").font(.mono(10)).foregroundStyle(Color.muted) }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                Text("Changes apply from the next round. Earlier rounds keep what was known then.")
                    .font(.mono(10)).foregroundStyle(Color.muted).padding(.top, 8)
            } else {
                Text("This experiment has no brief: everyone knows the whole context on the right.")
                    .font(.display(14, .regular)).foregroundStyle(Color.paper.opacity(0.8))
                Button(writing ? "writing the brief…" : "write a brief from this context") { Task { await write(e) } }
                    .buttonStyle(SButton(primary: true))
                    .disabled(writing || store.busy != nil || e.context.isEmpty)
                Text("A brief splits the context into facts you can mark public, insider or hidden.")
                    .font(.mono(10)).foregroundStyle(Color.muted)
            }
        }
    }

    private func sources(_ e: Experiment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Caps("read from")
            if let s = e.sources, !s.isEmpty {
                ForEach(s, id: \.self) { Text("✓ \($0)").font(.mono(11)) }
            } else {
                Text("typed notes only").font(.mono(11)).foregroundStyle(Color.muted)
            }
            Caps("raw context").padding(.top, 10)
            Text(e.context.isEmpty ? "(empty)" : e.context)
                .font(.mono(11)).foregroundStyle(Color.paper.opacity(0.75))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func retag(_ id: UUID) {
        guard var b = store.experiment?.brief, let i = b.facts.firstIndex(where: { $0.id == id }) else { return }
        b.facts[i].audience = b.facts[i].audience.next
        store.setBrief(b)
    }

    private func write(_ e: Experiment) async {
        writing = true
        defer { writing = false }
        if let b = await store.writeBrief(hypothesis: e.hypothesis, material: [("context", e.context)]) { store.setBrief(b) }
    }
}
