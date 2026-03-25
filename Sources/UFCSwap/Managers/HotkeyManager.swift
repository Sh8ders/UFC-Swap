import Carbon
import Foundation

protocol HotkeyManager {
    func installHotkeys(from definitions: [HotkeyDefinition], handler: @escaping @Sendable (HotkeyAction) -> Void) -> HotkeyRegistrationResult
    func unregisterAll()
}

struct HotkeyRegistrationResult {
    let loadedKey: String
    let registeredKey: String?
    let succeeded: Bool
    let message: String
}

final class GlobalHotkeyManager: HotkeyManager {
    private struct Registration {
        let action: HotkeyAction
        let reference: EventHotKeyRef?
    }

    private static let signature: OSType = 0x55464353
    private static var handlers: [UInt32: (@Sendable () -> Void)] = [:]
    private static var eventHandlerInstalled = false

    private var registrations: [UInt32: Registration] = [:]
    private var nextIdentifier: UInt32 = 1

    init() {
        Self.installEventHandlerIfNeeded()
    }

    func installHotkeys(from definitions: [HotkeyDefinition], handler: @escaping @Sendable (HotkeyAction) -> Void) -> HotkeyRegistrationResult {
        unregisterAll()

        let definition = AppConfigValidator.normalizeToggleHotkey(definitions)
        AppLogger.startup("loaded hotkey from config: \(definition.key)")
        AppLogger.hotkeys.info("Registering function-key hotkey action=\(definition.action.rawValue, privacy: .public) key=\(definition.key, privacy: .public)")

        guard let keyCode = Self.keyCode(for: definition.key) else {
            let message = "Hotkey registration failed: unsupported function key \(definition.key)"
            AppLogger.hotkeys.error("\(message, privacy: .public)")
            return HotkeyRegistrationResult(
                loadedKey: definition.key,
                registeredKey: nil,
                succeeded: false,
                message: message
            )
        }

        let identifier = nextIdentifier
        nextIdentifier += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            0,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        guard status == noErr else {
            let message = "Hotkey registration failed for \(definition.key) with status \(status)"
            AppLogger.startup("hotkey registration succeeded: false")
            AppLogger.hotkeys.error("\(message, privacy: .public)")
            return HotkeyRegistrationResult(
                loadedKey: definition.key,
                registeredKey: nil,
                succeeded: false,
                message: message
            )
        }

        registrations[identifier] = Registration(action: definition.action, reference: reference)
        Self.handlers[identifier] = {
            AppLogger.startup("hotkey is pressed: \(definition.key)")
            AppLogger.hotkeys.info("Triggered hotkey action=\(definition.action.rawValue, privacy: .public) key=\(definition.key, privacy: .public)")
            handler(definition.action)
        }

        AppLogger.startup("hotkey registration succeeded: true")
        AppLogger.hotkeys.info("Registered hotkey id=\(identifier) action=\(definition.action.rawValue, privacy: .public) key=\(definition.key, privacy: .public)")
        return HotkeyRegistrationResult(
            loadedKey: definition.key,
            registeredKey: definition.key,
            succeeded: true,
            message: "Hotkey registered: \(definition.key)"
        )
    }

    func unregisterAll() {
        for (identifier, registration) in registrations {
            if let reference = registration.reference {
                UnregisterEventHotKey(reference)
            }
            Self.handlers.removeValue(forKey: identifier)
            AppLogger.hotkeys.info("Unregistered hotkey id=\(identifier) action=\(registration.action.rawValue, privacy: .public)")
        }
        registrations.removeAll()
    }

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.handleHotKeyEvent,
            1,
            &eventSpec,
            nil,
            nil
        )

        eventHandlerInstalled = true
        AppLogger.hotkeys.info("Installed global hotkey event handler")
    }

    private static func keyCode(for key: String) -> Int? {
        FunctionKeyMap.keyCode(for: key)
    }

    private static let handleHotKeyEvent: EventHandlerUPP = { _, event, _ in
        guard let event else { return noErr }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            AppLogger.hotkeys.error("Failed reading hotkey event parameter status=\(status)")
            return status
        }

        handlers[hotKeyID.id]?()
        return noErr
    }
}
