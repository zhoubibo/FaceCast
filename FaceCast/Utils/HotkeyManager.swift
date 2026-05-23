import Carbon.HIToolbox

/// Registers global keyboard shortcuts for recording control via Carbon.
///
/// Carbon hot keys are system-wide, consume the keystroke, and need no
/// accessibility permission — unlike `NSEvent` global monitors.
///
/// Defaults: ⌘⇧2 toggles recording, ⌘⇧1 toggles pause.
final class HotkeyManager {
    var onToggleRecording: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onToggleOverlayVisibility: (() -> Void)?
    var onSetOverlayFullscreen: (() -> Void)?
    var onSetOverlayFloating: (() -> Void)?
    var onToggleMicrophoneMuted: (() -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    private static let signature: OSType = 0x46435354 // "FCST"
    private static let toggleRecordingID: UInt32 = 1
    private static let togglePauseID: UInt32 = 2
    private static let toggleOverlayVisibilityID: UInt32 = 3
    private static let setOverlayFullscreenID: UInt32 = 4
    private static let setOverlayFloatingID: UInt32 = 5
    private static let toggleMicrophoneMutedID: UInt32 = 6

    func registerDefaults() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hotKeyID)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handle(id: hotKeyID.id)
            return noErr
        }, 1, &eventType, context, &handlerRef)

        register(id: Self.toggleRecordingID,
                 keyCode: UInt32(kVK_ANSI_2),
                 modifiers: UInt32(cmdKey | shiftKey))
        register(id: Self.togglePauseID,
                 keyCode: UInt32(kVK_ANSI_1),
                 modifiers: UInt32(cmdKey | shiftKey))
        register(id: Self.toggleOverlayVisibilityID,
                 keyCode: UInt32(kVK_ANSI_Q),
                 modifiers: UInt32(optionKey))
        register(id: Self.setOverlayFullscreenID,
                 keyCode: UInt32(kVK_ANSI_O),
                 modifiers: UInt32(optionKey))
        register(id: Self.setOverlayFloatingID,
                 keyCode: UInt32(kVK_ANSI_I),
                 modifiers: UInt32(optionKey))
        register(id: Self.toggleMicrophoneMutedID,
                 keyCode: UInt32(kVK_ANSI_P),
                 modifiers: UInt32(optionKey))
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        handlerRef = nil
    }

    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRefs.append(ref)
        }
    }

    private func handle(id: UInt32) {
        DispatchQueue.main.async { [weak self] in
            switch id {
            case Self.toggleRecordingID: self?.onToggleRecording?()
            case Self.togglePauseID: self?.onTogglePause?()
            case Self.toggleOverlayVisibilityID: self?.onToggleOverlayVisibility?()
            case Self.setOverlayFullscreenID: self?.onSetOverlayFullscreen?()
            case Self.setOverlayFloatingID: self?.onSetOverlayFloating?()
            case Self.toggleMicrophoneMutedID: self?.onToggleMicrophoneMuted?()
            default: break
            }
        }
    }
}
