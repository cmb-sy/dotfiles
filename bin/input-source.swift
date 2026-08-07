// Report or change the active macOS keyboard input source.
//
// Neovim cannot see the IME state: the input method sits above the terminal and
// hands down finished characters, so the editor has no idea whether the next
// keystroke will produce "a" or "あ". Asking the OS is the only way.
//
//   input-source                  print the current source id
//   input-source --label          print a short label for the current source
//   input-source --label-for <id> print the label a given id maps to
//   input-source --set <id>       switch to that source
//
// --label-for exists so the id-to-label mapping can be asserted on behaviour
// without switching the machine's input source to check it.
//
// Built to a cached binary by bin/input-source -- running this through
// `#!/usr/bin/swift` costs ~2.4s per call because it compiles every time, which
// is far too slow to poll.

import Carbon
import Foundation

func currentSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
        return nil
    }
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

// A label rather than the id, because the id is long and the status line has
// one cell to spare. Japanese input methods carry the mode in the id.
func label(for id: String) -> String {
    let lower = id.lowercased()
    if lower.contains("inputmethod.japanese") || lower.contains("kotoeri") {
        if lower.hasSuffix(".roman") { return "A" }      // 英数 inside the Japanese IME
        if lower.contains("katakana") { return "カ" }
        return "あ"
    }
    return "A"
}

func set(id target: String) -> Bool {
    // Only enabled sources can be selected, so search the enabled list rather
    // than creating one.
    let filter = [kTISPropertyInputSourceID as String: target] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
          CFArrayGetCount(list) > 0 else {
        return false
    }
    let raw = CFArrayGetValueAtIndex(list, 0)
    let source = Unmanaged<TISInputSource>.fromOpaque(raw!).takeUnretainedValue()
    return TISSelectInputSource(source) == noErr
}

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--label-for" {
    guard args.count == 2 else {
        FileHandle.standardError.write("usage: input-source --label-for <id>\n".data(using: .utf8)!)
        exit(64)
    }
    print(label(for: args[1]))
    exit(0)
}

if args.first == "--set" {
    guard args.count == 2 else {
        FileHandle.standardError.write("usage: input-source --set <id>\n".data(using: .utf8)!)
        exit(64)
    }
    exit(set(id: args[1]) ? 0 : 1)
}

guard let id = currentSourceID() else {
    FileHandle.standardError.write("input-source: no current source\n".data(using: .utf8)!)
    exit(1)
}

print(args.first == "--label" ? label(for: id) : id)
