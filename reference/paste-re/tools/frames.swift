import AppKit
import CoreGraphics
import Foundation

let app = CommandLine.arguments[1]
let out = CommandLine.arguments[2]
let count = Int(CommandLine.arguments[3]) ?? 40

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
guard let win = list.first(where: { ($0[kCGWindowOwnerName as String] as? String) == app }),
      let wid = win[kCGWindowNumber as String] as? UInt32,
      let bounds = win[kCGWindowBounds as String] as? [String: CGFloat] else {
    print("window not found"); exit(1)
}
let rect = CGRect(x: bounds["X"]!, y: bounds["Y"]!,
                  width: bounds["Width"]!, height: bounds["Height"]!)
print("window rect (points):", rect)

let start = Date()
for i in 0..<count {
    // -x 静音，-R 限定窗口矩形（同一坐标空间），取到的是合成后的窗口画面
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-R",
                   "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))",
                   String(format: "%@/f%03d.png", out, i)]
    try? p.run(); p.waitUntilExit()
    let t = Date().timeIntervalSince(start) * 1000
    FileHandle.standardError.write("frame \(i) at \(String(format: "%.1f", t)) ms\n".data(using: .utf8)!)
}
print("captured \(count)")
