import Charts
import SwiftUI

struct ReportScreen: View {
    @Environment(Store.self) private var store

    var body: some View {
        if let e = store.experiment {
            VStack(spacing: 0) {
                ExperimentBar {
                    Button(e.report == nil ? "generate report" : "regenerate") { Task { await store.report() } }
                        .buttonStyle(SButton(primary: e.report == nil))
                        .disabled(store.busy != nil || e.branches.allSatisfy { $0.round == 0 })
                        .help("Write a report from every branch (⇧⌘R)")
                    ExportMenu(title: "export ▾", kinds: [.experiment, .report])
                    ExportMenu(title: "share bundle", kinds: [.bundle])
                }
                HStack(spacing: 0) {
                    ScrollView { left(e).padding(32) }
                    Rectangle().fill(Color.line).frame(width: 1)
                    ScrollView { right(e).padding(24) }.frame(width: 420).background(Color.sidebar)
                }
            }
        }
    }

    private func color(_ i: Int) -> Color { i == 0 ? .paper : i == 1 ? .ember : .muted }
    private struct Point: Identifiable {
        var branch: String
        var round: Int
        var mood: Double
        var color: Color
        var first: Bool
        var id: String { "\(branch)-\(round)" }
    }

    private func sentimentChart(_ e: Experiment) -> some View {
        let pts: [Point] = e.branches.enumerated().flatMap { i, b in
            b.moodByRound.enumerated().map { r, m in Point(branch: b.name, round: r, mood: m, color: color(i), first: i == 0) }
        }
        let fork = forkRound(e)
        let last = maxRound(e)
        return Chart {
            RuleMark(y: .value("neutral", 0))
                .foregroundStyle(Color.dim)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            if let fork {
                RuleMark(x: .value("fork", fork))
                    .foregroundStyle(Color.dim)
                    .annotation(position: .top, alignment: .leading) { Text("fork").font(.mono(10)).foregroundStyle(Color.muted) }
            }
            ForEach(pts) { p in
                LineMark(x: .value("round", p.round), y: .value("mood", p.mood), series: .value("branch", p.branch))
                    .foregroundStyle(p.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                PointMark(x: .value("round", p.round), y: .value("mood", p.mood))
                    .foregroundStyle(p.color)
                    .symbol(p.first ? .circle : .diamond)
                    .symbolSize(36)
            }
        }
        .chartYScale(domain: -1...1)
        .chartXScale(domain: 0...last, range: .plotDimension(startPadding: 8, endPadding: 24))
        .chartXAxis { roundAxis(last, fork: fork) }
        .chartYAxis { moodAxis }
    }

    private func roundAxis(_ last: Int, fork: Int?) -> some AxisContent {
        AxisMarks(values: Array(1...last)) { v in
            AxisValueLabel {
                Text("r\(v.as(Int.self) ?? 0)").font(.mono(10)).foregroundStyle(v.as(Int.self) == fork ? Color.ember : Color.muted)
            }
        }
    }

    private var moodAxis: some AxisContent {
        AxisMarks(position: .leading, values: [-0.6, 0, 0.6]) { v in
            AxisGridLine().foregroundStyle(Color.line)
            AxisValueLabel { Text(signed(v.as(Double.self) ?? 0)).font(.mono(10)).foregroundStyle(Color.muted) }
        }
    }

    private func maxRound(_ e: Experiment) -> Int { max(1, e.branches.map(\.round).max() ?? 1) }
    private func forkRound(_ e: Experiment) -> Int? {
        e.branches.dropFirst().compactMap { $0.parent.flatMap { Int($0.split(separator: "r").last ?? "") } }.min()
    }

    private func left(_ e: Experiment) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("what if").font(.mono(11)).foregroundStyle(Color.muted)
                Text(e.hypothesis).font(.display(30))
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Caps("community sentiment by round")
                    Spacer()
                    ForEach(Array(e.branches.enumerated()), id: \.element.id) { i, b in
                        Text("\(i == 0 ? "●" : "◆") \(b.title)").font(.mono(10)).foregroundStyle(color(i))
                    }
                }
                sentimentChart(e)
                .frame(height: 240)
            }
            .card(padding: 18)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                ForEach(Array(e.branches.enumerated()), id: \.element.id) { i, b in
                    let summary = e.report?.branches?.first { $0.name == b.name }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(i == 0 ? "●" : "◆") \(b.name) · \(summary?.summary ?? b.label ?? "\(b.round) rounds · \(b.events.count) events")")
                            .font(.mono(11)).foregroundStyle(color(i))
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 14) {
                            stat(signed(Engine.averageMood(b)), "final sentiment", color(i))
                            ForEach(summary?.metrics ?? [
                                .init(label: "on board", value: "\(b.characters.filter { $0.mood > 0 }.count) / \(b.characters.count)"),
                                .init(label: "posts", value: "\(b.posts.count)"),
                            ], id: \.self) { m in stat(m.value, m.label, color(i)) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 18)
                }
            }
            if e.branches.count > 1, let d = e.report?.divergence {
                VStack(alignment: .leading, spacing: 8) {
                    Caps("where they diverged")
                    Text(d).font(.display(14, .regular))
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.display(28)).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.mono(10)).foregroundStyle(Color.muted)
        }
    }

    private func right(_ e: Experiment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Caps("report")
                Spacer()
                if let updated = e.report?.updated {
                    Text("updated \(updated.formatted(.relative(presentation: .named)))").font(.mono(10)).foregroundStyle(Color.muted)
                }
            }
            if let r = e.report {
                Text(r.headline).font(.display(20))
                ForEach(Array(r.findings.enumerated()), id: \.offset) { i, f in
                    VStack(alignment: .leading, spacing: 8) {
                        (Text("0\(i + 1)  ").foregroundStyle(Color.ember) + Text(f.text)).font(.display(13, .regular))
                        FlowLayout(spacing: 6) {
                            ForEach(f.refs, id: \.self) { ref in
                                if let hit = Engine.resolve(ref, in: e) {
                                    Button { store.focus(ref) } label: {
                                        HStack(spacing: 5) {
                                            Avatar(name: hit.post.author, size: 14)
                                            Text("\(e.branches.count > 1 ? "\(hit.branch.name) · " : "")r\(hit.post.round) · @\(hit.post.author)").font(.mono(10))
                                        }
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.line))
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .help(hit.post.text)
                                }
                            }
                        }
                    }
                }
                Caps("questions to investigate").padding(.top, 8)
                ForEach(r.questions, id: \.self) { Text("→ \($0)").font(.display(13, .regular)) }
            } else {
                Text("Run a few rounds, fork if you like, then generate a report. Every finding links back to the posts behind it.")
                    .font(.mono(11)).foregroundStyle(Color.muted)
            }
            Text("Simulations surface possible reactions. Treat them as hypotheses to investigate, not evidence.")
                .font(.mono(10)).foregroundStyle(Color.muted).padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
