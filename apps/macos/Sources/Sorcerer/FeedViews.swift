import Charts
import SwiftUI

/// The community as a map: everyone on a ring, their ties, and what the people who spoke
/// this round said.
struct WorldView: View {
    @Environment(Store.self) private var store
    var branch: Branch

    var body: some View {
        let latest = branch.posts.filter { $0.round == branch.round }
        let said = Dictionary(latest.map { ($0.author, $0.text) }, uniquingKeysWith: { _, last in last })
        let events = branch.events.filter { $0.round == branch.round || $0.round == branch.round + 1 }
        let away = Engine.away(branch)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("round \(branch.round) · \(said.count) of \(branch.characters.count) spoke")
                    .font(.mono(11)).foregroundStyle(Color.muted)
                Spacer()
                ForEach(events) { ev in
                    Text("⚡ r\(ev.round) \(ev.text)").font(.mono(10)).foregroundStyle(Color.ember).lineLimit(1)
                }
            }
            GeometryReader { geo in
                let spots = Self.layout(branch.characters.map(\.handle), in: geo.size)
                ZStack(alignment: .topLeading) {
                    Dots(seed: UInt32(branch.round + 21), count: 140)
                    Canvas { ctx, _ in
                        for c in branch.characters {
                            for other in (c.ties ?? [:]).keys {
                                guard let a = spots[c.handle], let b = spots[other] else { continue }
                                var path = Path()
                                path.move(to: a)
                                path.addLine(to: b)
                                let hot = said[c.handle] != nil && said[other] != nil
                                ctx.stroke(path, with: .color(hot ? Color.ember.opacity(0.7) : Color.dim.opacity(0.5)),
                                           style: StrokeStyle(lineWidth: hot ? 1.5 : 1, dash: [3, 4]))
                            }
                        }
                    }
                    ForEach(branch.characters) { c in
                        let p = spots[c.handle] ?? .zero
                        VStack(spacing: 6) {
                            if let text = said[c.handle] {
                                Text("“\(text.prefix(70))\(text.count > 70 ? "…" : "")”")
                                    .font(.display(11, .regular)).lineLimit(3)
                                    .frame(width: 170)
                                    .padding(8)
                                    .background(Color.panel, in: .rect(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ember.opacity(0.6)))
                            }
                            Button { store.go(.character(c.handle)) } label: {
                                VStack(spacing: 4) {
                                    Avatar(name: c.handle, size: 40, highlight: said[c.handle] != nil)
                                        .opacity(away.contains(c.handle) ? 0.35 : 1)
                                    Text("@\(c.handle) \(signed(c.mood))").font(.mono(10))
                                        .foregroundStyle(said[c.handle] != nil ? Color.paper : Color.muted)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .fixedSize()
                        // Anchor on the avatar, bubbles grow upward.
                        .position(x: p.x, y: p.y - (said[c.handle] != nil ? 34 : 0))
                    }
                }
            }
        }
        .padding(18)
    }

    /// Everyone on an ellipse, starting at the top, in cast order.
    static func layout(_ handles: [String], in size: CGSize) -> [String: CGPoint] {
        let cx = size.width / 2, cy = size.height / 2 + 20
        let rx = max(60, size.width / 2 - 110), ry = max(60, size.height / 2 - 70)
        return Dictionary(uniqueKeysWithValues: handles.enumerated().map { i, h in
            let a = Double(i) / Double(max(handles.count, 1)) * 2 * .pi - .pi / 2
            return (h, CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a)))
        })
    }
}

/// Mood per character, round by round, and who the conversation revolves around.
struct GraphView: View {
    @Environment(Store.self) private var store
    var experiment: Experiment
    var branch: Branch
    @State private var focus: String?

    private static let palette: [UInt32] = [0xF0773A, 0xECEBE4, 0x6F7FE0, 0x4FA37D, 0xE0C24A, 0xC48A62, 0xB76E9E, 0x5FB8C9]

    var body: some View {
        let series = Engine.moodSeries(branch, start: experiment.cast)
        let handles = branch.characters.map(\.handle)
        let replies = Dictionary(grouping: branch.posts.compactMap(\.replyTo), by: { $0 }).mapValues(\.count)
        let maxReplies = max(1, replies.values.max() ?? 1)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Caps("mood by character")
                        Spacer()
                        Text(focus.map { "showing @\($0) · click again for everyone" } ?? "click a name to focus")
                            .font(.mono(10)).foregroundStyle(Color.muted)
                    }
                    moodChart(series, handles)
                    .frame(height: 280)
                    FlowLayout(spacing: 8) {
                        ForEach(Array(handles.enumerated()), id: \.element) { i, h in
                            let s = series[h] ?? []
                            let delta = (s.last ?? 0) - (s.first ?? 0)
                            Button { focus = focus == h ? nil : h } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(color(i)).frame(width: 8, height: 8)
                                    Avatar(name: h, size: 16)
                                    Text("@\(h) \(signed(s.last ?? 0))").font(.mono(10))
                                    Text(delta >= 0.05 ? "↑" : delta <= -0.05 ? "↓" : "·")
                                        .font(.mono(10)).foregroundStyle(delta < 0 ? Color.ember : Color.muted)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .overlay(Capsule().stroke(focus == h ? color(i) : Color.line))
                                .opacity(focus == nil || focus == h ? 1 : 0.5)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .card(padding: 18)

                if let acts = experiment.actions, !(branch.actions ?? []).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Caps("actions by round")
                            Spacer()
                            Text("people whose latest action it is").font(.mono(10)).foregroundStyle(Color.muted)
                        }
                        countChart(Engine.actionSeries(branch, acts).map { ($0.act, $0.counts.enumerated().map { ($0.offset, $0.element) }) })
                            .frame(height: 200)
                    }
                    .card(padding: 18)
                }
                ForEach(pollSeries, id: \.question) { s in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Caps("poll · \(s.question)")
                            Spacer()
                            Text("asked \(s.runs) times").font(.mono(10)).foregroundStyle(Color.muted)
                        }
                        countChart(s.lines).frame(height: 180)
                    }
                    .card(padding: 18)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Caps("who gets replies · influence")
                    ForEach(handles.sorted { (replies[$0] ?? 0) > (replies[$1] ?? 0) }, id: \.self) { h in
                        Button { store.go(.character(h)) } label: {
                            HStack(spacing: 10) {
                                Avatar(name: h, size: 18)
                                Text("@\(h)").font(.mono(11)).frame(width: 110, alignment: .leading)
                                GeometryReader { geo in
                                    Rectangle().fill(Color.ember.opacity(0.75))
                                        .frame(width: geo.size.width * CGFloat(replies[h] ?? 0) / CGFloat(maxReplies))
                                }
                                .frame(height: 8)
                                Text("\(replies[h] ?? 0)").font(.mono(11)).foregroundStyle(Color.muted).frame(width: 28, alignment: .trailing)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: 18)
            }
            .padding(18)
        }
    }

    private func color(_ i: Int) -> Color { Color(hex: Self.palette[i % Self.palette.count]) }

    /// Questions asked more than once, as one line per option: how many picked it each time.
    private var pollSeries: [(question: String, runs: Int, lines: [(String, [(Int, Int)])])] {
        Dictionary(grouping: branch.polls ?? [], by: \.question).filter { $0.value.count > 1 }
            .sorted { $0.key < $1.key }
            .map { q, runs in
                let sorted = runs.sorted { $0.round < $1.round }
                let options = sorted.last?.options ?? []
                return (q, runs.count, options.map { o in (o, sorted.map { ($0.round, $0.count(o)) }) })
            }
    }

    /// One plotted count. Precomputed so the chart body stays simple enough for every Swift compiler.
    private struct Count: Identifiable {
        var series: String
        var round: Int
        var n: Int
        var color: Color
        var id: String { "\(series)-\(round)" }
    }

    private func countChart(_ lines: [(String, [(Int, Int)])]) -> some View {
        let pts = lines.enumerated().flatMap { i, line in line.1.map { Count(series: line.0, round: $0.0, n: $0.1, color: color(i)) } }
        let top = max(1, pts.map(\.n).max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            Chart(pts) { p in
                LineMark(x: .value("round", p.round), y: .value("people", p.n), series: .value("what", p.series))
                    .foregroundStyle(p.color)
                    .interpolationMethod(.stepEnd)
                PointMark(x: .value("round", p.round), y: .value("people", p.n))
                    .foregroundStyle(p.color).symbolSize(16)
            }
            .chartYScale(domain: 0...top)
            .chartXAxis { roundAxis(max(1, branch.round)) }
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(0...top)) { v in
                    AxisGridLine().foregroundStyle(Color.line)
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.mono(10)).foregroundStyle(Color.muted) }
                }
            }
            FlowLayout(spacing: 12) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    HStack(spacing: 6) {
                        Circle().fill(color(i)).frame(width: 8, height: 8)
                        Text("\(line.0) · \(line.1.last?.1 ?? 0)").font(.mono(10))
                    }
                }
            }
        }
    }

    /// One plotted point. Precomputed so the chart body stays simple enough for every Swift compiler.
    private struct Point: Identifiable {
        var who: String
        var round: Int
        var mood: Double
        var color: Color
        var on: Bool
        var id: String { "\(who)-\(round)" }
    }

    private func points(_ series: [String: [Double]], _ handles: [String]) -> [Point] {
        handles.enumerated().flatMap { i, h in
            (series[h] ?? []).enumerated().map { r, m in
                Point(who: h, round: r, mood: m, color: color(i), on: focus == nil || focus == h)
            }
        }
    }

    private func moodChart(_ series: [String: [Double]], _ handles: [String]) -> some View {
        let pts = points(series, handles)
        let last = max(1, branch.round)
        return Chart {
            RuleMark(y: .value("neutral", 0))
                .foregroundStyle(Color.dim)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(pts) { p in
                LineMark(x: .value("round", p.round), y: .value("mood", p.mood), series: .value("who", p.who))
                    .foregroundStyle(p.color)
                    .lineStyle(StrokeStyle(lineWidth: focus == p.who ? 2.5 : 1.5))
                    .opacity(p.on ? 1 : 0.15)
                PointMark(x: .value("round", p.round), y: .value("mood", p.mood))
                    .foregroundStyle(p.color)
                    .symbolSize(focus == p.who ? 30 : 14)
                    .opacity(p.on ? 1 : 0.15)
            }
        }
        .chartYScale(domain: -1...1)
        .chartXScale(domain: 0...last, range: .plotDimension(startPadding: 12, endPadding: 24))
        .chartXAxis { roundAxis(last) }
        .chartYAxis { moodAxis }
    }

    private func roundAxis(_ last: Int) -> some AxisContent {
        AxisMarks(values: Array(0...last)) { v in
            AxisValueLabel { Text("r\(v.as(Int.self) ?? 0)").font(.mono(10)).foregroundStyle(Color.muted) }
        }
    }

    private var moodAxis: some AxisContent {
        AxisMarks(position: .leading, values: [-1, -0.5, 0, 0.5, 1]) { v in
            AxisGridLine().foregroundStyle(Color.line)
            AxisValueLabel { Text(signed(v.as(Double.self) ?? 0)).font(.mono(10)).foregroundStyle(Color.muted) }
        }
    }
}
