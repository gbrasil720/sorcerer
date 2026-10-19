import SwiftUI
import UniformTypeIdentifiers

struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension ExportKind {
    var label: String {
        switch self {
        case .experiment: "Experiment with history…"
        case .bundle: "Fresh scenario for others to run…"
        case .report: "Report as Markdown…"
        }
    }
}

extension Store {
    func exportPayload(_ k: ExportKind) -> (data: Data, type: UTType, name: String)? {
        let name = experiment?.name ?? "world"
        switch k {
        case .experiment: return exportData(fresh: false).map { ($0, .json, "\(name).sorcerer.json") }
        case .bundle: return exportData(fresh: true).map { ($0, .json, "\(name)-scenario.sorcerer.json") }
        case .report: return experiment?.report == nil ? nil : (Data(reportMarkdown().utf8), .plainText, "\(name)-report.md")
        }
    }
}

/// One button (single kind) or a menu (several). It only asks; `Exporter` shows the save panel,
/// so menus, the palette and the menu bar can all export the same way.
struct ExportMenu: View {
    @Environment(Store.self) private var store
    var title: String
    var kinds: [ExportKind]

    var body: some View {
        if kinds.count == 1 {
            Button(title) { store.exporting = kinds[0] }.buttonStyle(SButton())
        } else {
            Menu {
                ForEach(kinds, id: \.self) { k in
                    Button(k.label) { store.exporting = k }.disabled(store.exportPayload(k) == nil)
                }
            } label: {
                Text(title)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(SButton())
            .fixedSize()
        }
    }
}

/// Hosts the single save panel for every export in the app.
struct Exporter: ViewModifier {
    @Environment(Store.self) private var store

    func body(content: Content) -> some View {
        let payload = store.exporting.flatMap { store.exportPayload($0) }
        content.fileExporter(
            isPresented: Binding(get: { payload != nil }, set: { if !$0 { store.exporting = nil } }),
            document: payload.map { ExportFile(data: $0.data) },
            contentType: payload?.type ?? .json,
            defaultFilename: payload?.name
        ) { _ in store.exporting = nil }
    }
}
