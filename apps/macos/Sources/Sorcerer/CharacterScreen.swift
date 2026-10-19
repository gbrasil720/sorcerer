import SwiftUI

struct CharacterScreen: View {
    @Environment(Store.self) private var store
    var handle: String
    @State private var question = ""
    @State private var inWorld = false
    @State private var editing: Persona?
    @State private var adding = false
    @State private var dressing: String?

    var body: some View {
        if let e = store.experiment, let b = store.branch, let p = b.characters.first(where: { $0.handle == handle }) {
            VStack(spacing: 0) {
                ExperimentBar {
                    Button("appearance") { dressing = p.handle }.buttonStyle(SButton())
                    Button("edit persona") { editing = p }.buttonStyle(SButton())
                    Button("duplicate") { store.duplicate(p) }.buttonStyle(SButton())
                }
                HStack(spacing: 0) {
                    community(e, b)
                    Rectangle().fill(Color.line).frame(width: 1)
                    ScrollView { profile(e, p, b).padding(32).frame(maxWidth: .infinity, alignment: .leading) }
                    Rectangle().fill(Color.line).frame(width: 1)
                    chat(p).frame(width: 420)
                }
            }
            .sheet(item: $editing) { EditPersona(persona: $0) }
            .sheet(item: Binding(get: { dressing.map(Dressing.init) }, set: { dressing = $0?.id })) { d in
                AvatarEditor(handle: d.id, look: store.look(of: d.id) ?? .derived(from: d.id))
            }
        }
    }

    /// Everyone in this world, one click apart.
    private func community(_ e: Experiment, _ b: Branch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Caps("\(e.community ?? "community") · \(b.characters.count)")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(b.characters) { c in
                        let on = c.handle == handle
                        Button { store.go(.character(c.handle)) } label: {
                            HStack(spacing: 10) {
                                Avatar(name: c.handle, size: 26)
                                Text("@\(c.handle)").font(.mono(12, on ? .semibold : .regular)).lineLimit(1)
                                Spacer()
                                Text(signed(c.mood)).font(.mono(10)).foregroundStyle(c.mood < 0 ? Color.ember : Color.muted)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(on ? Color.panel : .clear, in: .rect(cornerRadius: 6))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    Button(adding ? "summoning…" : "+ add character") {
                        adding = true
                        Task { await store.addCharacter(); adding = false }
                    }
                    .buttonStyle(.plain).font(.mono(11)).foregroundStyle(Color.muted)
                    .padding(.horizontal, 8).padding(.top, 8)
                    .disabled(store.busy != nil)
                }
            }
        }
        .padding(16)
        .frame(width: 220)
        .background(Color.sidebar)
    }

    private func profile(_ e: Experiment, _ p: Persona, _ b: Branch) -> some View {
        let posts = b.posts.filter { $0.author == p.handle }
        let start = e.cast?.first { $0.handle == p.handle }?.mood
        return VStack(alignment: .leading, spacing: 24) {
            Button { dressing = p.handle } label: {
                Avatar(name: p.handle, size: 136)
                    .padding(10)
                    .background(Color.panel, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.line))
                    .overlay(alignment: .bottomTrailing) {
                        Text("✎").font(.mono(12)).padding(6).background(Color.line, in: .circle).offset(x: 6, y: 6)
                    }
            }
            .buttonStyle(.plain)
            .help("Change appearance")
            VStack(alignment: .leading, spacing: 8) {
                Text("@\(p.handle)").font(.display(42))
                Text(p.role).font(.display(15, .regular)).foregroundStyle(Color.paper.opacity(0.85))
                if !p.bio.isEmpty { Text(p.bio).font(.display(13, .regular)).foregroundStyle(Color.muted) }
                HStack(spacing: 14) {
                    Text("mood \(signed(p.mood))")
                    if let start, abs(start - p.mood) >= 0.05 {
                        Text("\(p.mood > start ? "↑" : "↓") from \(signed(start))").foregroundStyle(p.mood > start ? Color.paper : Color.ember)
                    }
                    Text("\(posts.count) posts")
                    Text("\(p.memories.count) memories")
                    Text("\(p.ties?.count ?? 0) ties")
                }
                .font(.mono(11)).foregroundStyle(Color.muted)
            }
            if !p.traits.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Caps("personality")
                    ForEach(Engine.traitNames.filter { p.traits[$0] != nil }, id: \.self) { t in
                        HStack {
                            Text(t).font(.mono(11)).foregroundStyle(Color.muted)
                            Spacer()
                            Meter(value: p.traits[t] ?? 0)
                        }
                        .frame(maxWidth: 520)
                    }
                }
            }
            if !p.interests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Caps("interests")
                    FlowRow(items: p.interests) { Chip(text: $0, on: false) }.frame(maxWidth: 520)
                }
            }
            if !p.goals.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Caps("goals")
                    ForEach(p.goals, id: \.self) { Text("→ \($0)").font(.display(14, .regular)) }
                }
            }
            if let ties = p.ties, !ties.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Caps("ties")
                    ForEach(ties.keys.sorted(), id: \.self) { other in
                        Button { store.go(.character(other)) } label: {
                            HStack(spacing: 8) {
                                Avatar(name: other, size: 20)
                                Text("@\(other)").font(.mono(11, .semibold))
                                Text(ties[other] ?? "").font(.mono(11)).foregroundStyle(Color.muted)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !p.memories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Caps("memories")
                    ForEach(p.memories.reversed(), id: \.self) { Text($0).font(.mono(11)).foregroundStyle(Color.paper.opacity(0.8)) }
                }
            }
        }
    }

    private func chat(_ p: Persona) -> some View {
        let lines = store.chats[p.handle] ?? []
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Avatar(name: p.handle, size: 26)
                    Text("Talk to @\(p.handle)").font(.display(15))
                    Spacer()
                    Tabs(options: [(false, "off the record"), (true, "in-world")], selection: $inWorld)
                }
                Text(inWorld
                     ? "In-world: \(p.handle) remembers this conversation and it can shape later rounds."
                     : "Off the record: \(p.handle) answers from memory. Nothing is added to the simulation.")
                    .font(.mono(10)).foregroundStyle(Color.muted)
            }
            .padding(16)
            Rectangle().fill(Color.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        Text(l.text).font(.display(13, .regular)).textSelection(.enabled)
                            .padding(12)
                            .background(l.fromUser ? Color.line : Color.ink, in: .rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(l.fromUser ? .clear : Color.line))
                            .frame(maxWidth: 320, alignment: l.fromUser ? .trailing : .leading)
                            .frame(maxWidth: .infinity, alignment: l.fromUser ? .trailing : .leading)
                    }
                    if let d = store.chatDraft, d.handle == p.handle {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("@\(p.handle) is typing").font(.mono(10)).foregroundStyle(Color.ember)
                                TypingDots()
                            }
                            if !d.text.isEmpty {
                                (Text(d.text) + Text("▍").foregroundStyle(Color.ember)).font(.display(13, .regular))
                            }
                        }
                        .padding(12)
                        .background(Color.ink, in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ember.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .frame(maxWidth: 320, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom)
            HStack {
                TextField("Ask @\(p.handle) anything…", text: $question)
                    .textFieldStyle(.plain).font(.display(13, .regular))
                    .onSubmit { send(p) }
                Button("send") { send(p) }.buttonStyle(SButton(primary: true)).disabled(question.isEmpty || store.busy != nil)
            }
            .card()
            .padding(14)
        }
        .background(Color.sidebar)
    }

    private func send(_ p: Persona) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, store.busy == nil else { return }
        question = ""
        Task { await store.chat(with: p, q, inWorld: inWorld) }
    }
}

/// Edit who someone is. Changes apply to the branch you're looking at.
struct EditPersona: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var persona: Persona
    @State private var interests = ""
    @State private var goals = ""

    var body: some View {
        Form {
            Section("@\(persona.handle)") {
                TextField("Role", text: $persona.role)
                TextField("Bio", text: $persona.bio, axis: .vertical).lineLimit(2...4)
                TextField("Interests (comma separated)", text: $interests)
                TextField("Goals (one per line)", text: $goals, axis: .vertical).lineLimit(2...4)
            }
            Section("Personality") {
                ForEach(Engine.traitNames, id: \.self) { t in
                    Slider(value: Binding(get: { persona.traits[t] ?? 0.5 }, set: { persona.traits[t] = $0 })) {
                        Text(t).font(.mono(11))
                    }
                }
                Slider(value: $persona.mood, in: -1...1) { Text("mood \(signed(persona.mood))").font(.mono(11)) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    persona.interests = interests.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    persona.goals = goals.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    store.update(persona)
                    dismiss()
                }
            }
        }
        .onAppear {
            interests = persona.interests.joined(separator: ", ")
            goals = persona.goals.joined(separator: "\n")
        }
    }
}

private struct Dressing: Identifiable { var id: String }
