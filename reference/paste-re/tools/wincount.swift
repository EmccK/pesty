import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "Pesty" }
for w in mine {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("window layer=\(w[kCGWindowLayer as String] ?? "?") bounds=\(b)")
}
print("count=\(mine.count)")
