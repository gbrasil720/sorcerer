import Foundation

/// A local, explicit schema: importing never asks a model to invent missing character details.
enum CastCSV {
    static let maxBytes = 128_000
    static let example = """
    handle,role,bio,interests,goals,mood,insider
    ada,student,"Uses free notes, compares every price",notes|music,save money,-0.4,false
    ben,freelancer,Uses notes for client projects,sync|writing,work offline,0.2,true
    """
    static let columns = ["handle", "role", "bio", "interests", "goals", "mood", "insider"]

    static func read(_ url: URL) throws -> [Persona] {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        return try parse(file.read(upToCount: maxBytes + 1) ?? Data())
    }

    static func parse(_ data: Data) throws -> [Persona] {
        guard data.count <= maxBytes else { throw AIError(message: "CSV must be 128 KB or smaller.") }
        guard var text = String(data: data, encoding: .utf8) else { throw AIError(message: "Save the CSV as UTF-8.") }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        var rows = try records(text)
        guard !rows.isEmpty else { throw AIError(message: "The CSV is empty.") }
        let header = rows.removeFirst().map { $0.lowercased() }
        guard Set(header).count == header.count else { throw AIError(message: "CSV column names must be unique.") }
        guard ["handle", "role", "bio"].allSatisfy(header.contains) else {
            throw AIError(message: "CSV needs handle, role and bio columns.")
        }
        let unknown = header.filter { !columns.contains($0) }
        guard unknown.isEmpty else { throw AIError(message: "Unsupported CSV columns: " + unknown.joined(separator: ", ")) }
        guard (2...16).contains(rows.count) else { throw AIError(message: "Import between 2 and 16 characters.") }
        var seen = Set<String>()
        return try rows.enumerated().map { index, row in
            func fail(_ message: String) -> AIError { AIError(message: "CSV record \(index + 2): \(message)") }
            guard row.count == header.count else { throw fail("expected \(header.count) fields, found \(row.count).") }
            let values = Dictionary(uniqueKeysWithValues: zip(header, row))
            let handle = Engine.handle(values["handle"] ?? "")
            guard !handle.isEmpty, handle.count <= 32,
                  handle.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" }) else {
                throw fail("handle must be 1–32 letters, numbers, underscores or hyphens.")
            }
            guard seen.insert(handle).inserted else { throw fail("duplicate handle @\(handle).") }
            let role = values["role"] ?? "", bio = values["bio"] ?? ""
            guard !role.isEmpty, !bio.isEmpty else { throw fail("role and bio cannot be empty.") }
            let rawMood = values["mood"] ?? ""
            guard let mood = rawMood.isEmpty ? 0 : Double(rawMood), mood.isFinite, (-1...1).contains(mood) else {
                throw fail("mood must be a number from -1 to 1.")
            }
            let insider = (values["insider"] ?? "").lowercased()
            guard ["", "true", "false"].contains(insider) else { throw fail("insider must be true or false.") }
            func list(_ key: String) -> [String] {
                (values[key] ?? "").split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            return Persona(handle: handle, role: role, bio: bio,
                           interests: list("interests"), goals: list("goals"), mood: mood,
                           insider: insider == "true" ? true : nil)
        }
    }

    /// Commas, escaped quotes and embedded newlines; fail closed on malformed quoting.
    private static func records(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closed = false
        var chars = text.makeIterator()
        var current = chars.next()
        func finishField() {
            row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
            field = ""; closed = false
        }
        func finishRow() {
            finishField()
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            row = []
        }
        while let c = current {
            let next = chars.next()
            if quoted {
                if c == "\"" {
                    if next == "\"" {
                        field.append(c); current = chars.next(); continue
                    }
                    quoted = false; closed = true
                } else { field.append(c) }
            } else if c == "," { finishField() }
            else if c.isNewline { finishRow() }
            else if c == "\"", field.isEmpty, !closed { quoted = true }
            else {
                guard !closed, c != "\"" else { throw AIError(message: "Malformed CSV quoting near record \(rows.count + 1).") }
                field.append(c)
            }
            current = next
        }
        guard !quoted else { throw AIError(message: "CSV has an unclosed quoted field.") }
        if !field.isEmpty || !row.isEmpty || closed { finishRow() }
        return rows
    }
}
