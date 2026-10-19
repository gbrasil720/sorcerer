// Renders the app icon (pixel hat on ink) to a 1024px PNG.
// Usage: swift icon.swift out.png   (called by bundle.sh)
import AppKit

let hat = [ // same bitmap as Pixels.hat in Theme.swift
    ".o............",
    "owo......##...",
    ".o......##g...",
    ".......###g...",
    "......##o#g...",
    "......####g...",
    ".....#o####g..",
    ".....######g..",
    "....#######g..",
    "....oooooooO..",
    "...#########g.",
    "#############g",
    ".ddddddddddd..",
]
let colors: [Character: NSColor] = [
    "#": NSColor(red: 0.925, green: 0.922, blue: 0.894, alpha: 1),
    "o": NSColor(red: 0.941, green: 0.467, blue: 0.227, alpha: 1),
    "w": NSColor(red: 1, green: 0.973, blue: 0.933, alpha: 1),
    "O": NSColor(red: 0.71, green: 0.325, blue: 0.176, alpha: 1),
    "g": NSColor(red: 0.549, green: 0.537, blue: 0.514, alpha: 1),
    "d": NSColor(red: 0.431, green: 0.42, blue: 0.4, alpha: 1),
]

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
// macOS icon grid: 824pt body centered on a 1024 canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(
    starting: NSColor(red: 0.09, green: 0.09, blue: 0.085, alpha: 1),
    ending: NSColor(red: 0.035, green: 0.035, blue: 0.03, alpha: 1)
)!.draw(in: shape, angle: -90)
NSColor(white: 1, alpha: 0.08).setStroke()
shape.lineWidth = 4
shape.stroke()

let px = 40.0
let w = Double(hat[0].count) * px, h = Double(hat.count) * px
let origin = NSPoint(x: (size - w) / 2, y: (size - h) / 2 - 10)
for (row, line) in hat.enumerated() {
    for (col, c) in line.enumerated() {
        guard let color = colors[c] else { continue }
        color.setFill()
        // Flip rows: bitmap is top-down, AppKit is bottom-up.
        NSRect(x: origin.x + Double(col) * px, y: origin.y + h - Double(row + 1) * px, width: px, height: px).fill()
    }
}
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
