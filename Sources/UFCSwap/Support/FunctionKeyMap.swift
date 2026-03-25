import AppKit
import Carbon
import Foundation

enum FunctionKeyMap {
    private static let keyCodeToName: [UInt16: String] = [
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13",
        UInt16(kVK_F14): "F14",
        UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17",
        UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19"
    ]

    private static let nameToKeyCode: [String: Int] = Dictionary(
        uniqueKeysWithValues: keyCodeToName.map { ($1, Int($0)) }
    )

    static let supportedNames = (1...19).map { "F\($0)" }

    static func name(for keyCode: UInt16) -> String? {
        keyCodeToName[keyCode]
    }

    static func keyCode(for name: String) -> Int? {
        nameToKeyCode[name.uppercased()]
    }

    static func isFunctionKeyEvent(_ event: NSEvent) -> Bool {
        name(for: event.keyCode) != nil
    }
}
