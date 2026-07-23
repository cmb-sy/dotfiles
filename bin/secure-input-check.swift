#!/usr/bin/swift
// Print the PID holding macOS Secure Input Mode, or nothing if it's not
// enabled. Used by bin/secure-input-watch to detect apps (e.g. Ghostty)
// that enable Secure Input for a password prompt and fail to release it,
// which silently blocks other apps' keyboard shortcuts (e.g. Typeless).
import CoreGraphics
import Foundation

if let cfDict = CGSessionCopyCurrentDictionary() {
    let dict = cfDict as NSDictionary
    if let pid = dict["kCGSSessionSecureInputPID"] {
        print(pid)
    }
}
