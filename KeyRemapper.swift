import Cocoa
import Carbon

extension KeyRemapper {
    // 現在の入力ソースが日本語入力（IME）かどうかをチェック
    static func isJapaneseInputSourceActive() -> Bool {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        
        // 入力ソースのIDを取得
        guard let inputSourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
            return false
        }
        
        let sourceID = Unmanaged<CFString>.fromOpaque(inputSourceID).takeUnretainedValue() as String
        
        // 日本語入力ソースのIDパターンをチェック
        // com.apple.inputmethod.Japanese, com.apple.inputmethod.Kotoeri など
        return sourceID.contains("Japanese") || 
               sourceID.contains("Kotoeri") ||
               sourceID.contains("japanese")
    }
    
    // 変換候補ウィンドウが表示されているかどうかをチェック
    static func isConversionCandidateWindowVisible() -> Bool {
        // アクセシビリティAPIを使って変換候補ウィンドウを検索
        // すべてのアプリケーションを取得
        let runningApps = NSWorkspace.shared.runningApplications
        
        // 日本語入力メソッドのプロセスを探す
        for app in runningApps {
            if let bundleIdentifier = app.bundleIdentifier,
               (bundleIdentifier.contains("Japanese") || 
                bundleIdentifier.contains("Kotoeri") ||
                bundleIdentifier.contains("japanese")) {
                // 日本語入力メソッドのウィンドウをチェック
                let pid = app.processIdentifier
                let appElement = AXUIElementCreateApplication(pid)
                
                var windows: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows) == .success,
                   let windowsArray = windows as? [AXUIElement] {
                    for window in windowsArray {
                        // ウィンドウの子要素をチェックして、変換候補リストがあるか確認
                        var children: CFTypeRef?
                        if AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children) == .success,
                           let childrenArray = children as? [AXUIElement] {
                            for child in childrenArray {
                                var role: CFTypeRef?
                                if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success,
                                   let roleString = role as? String {
                                    // リストやテーブルがある場合は変換候補ウィンドウの可能性が高い
                                    if roleString == kAXListRole || roleString == kAXTableRole {
                                        return true
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return false
    }
}

// 物理キーコード（JIS / US 配列で同じ位置のキー）
enum KeyCode {
    static let m: Int64 = 46
    static let returnKey: Int64 = 36
    static let semicolon: Int64 = 41   // JIS: ;   US: ;
    static let colon: Int64 = 39       // JIS: :   US: '
    static let atMark: Int64 = 33      // JIS: @   US: [
    static let slash: Int64 = 44       // JIS: /   US: /
    static let left: CGKeyCode = 123
    static let right: CGKeyCode = 124
    static let down: CGKeyCode = 125
    static let up: CGKeyCode = 126
}

// HHKB の Fn レイヤーと同じ配置で、Ctrl+キー → Ctrl+矢印 に変換する
let arrowRemap: [Int64: CGKeyCode] = [
    KeyCode.semicolon: KeyCode.left,   // Ctrl+; → Ctrl+←
    KeyCode.colon: KeyCode.right,      // Ctrl+: → Ctrl+→
    KeyCode.atMark: KeyCode.up,        // Ctrl+@ → Ctrl+↑
    KeyCode.slash: KeyCode.down,       // Ctrl+/ → Ctrl+↓
]

enum RemapAction {
    case enter
    case arrow(CGKeyCode, shift: Bool)
}

class KeyRemapper {
    // イベントタップ（タイムアウトで無効化された際の再有効化に使用）
    nonisolated(unsafe) static var eventTap: CFMachPort?
    // keyDown 時に決めた変換を keyUp でも同じように適用するための記録（キー: 元のキーコード）
    nonisolated(unsafe) static var activeActions: [Int64: RemapAction] = [:]

    func start() {
        // アクセシビリティ権限をチェック
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("⚠️  アクセシビリティ権限が必要です")
            print("システム設定 → プライバシーとセキュリティ → アクセシビリティ")
            print("このアプリケーションを許可してください")

            // 権限ダイアログを表示
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            return
        }

        print("✅ キーリマッピングを開始します")
        print("  Ctrl+M → Enter（変換候補表示中は変換確定として通す）")
        print("  Ctrl+; → Ctrl+←   Ctrl+: → Ctrl+→")
        print("  Ctrl+@ → Ctrl+↑   Ctrl+/ → Ctrl+↓")
        print("  （Shift を併用すると Ctrl+Shift+矢印）")
        print("終了するには Ctrl+C を押してください\n")

        // イベントタップを作成
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                return KeyRemapper.handleEvent(proxy: proxy, type: type, event: event, refcon: refcon)
            },
            userInfo: nil
        ) else {
            print("❌ イベントタップの作成に失敗しました")
            return
        }

        KeyRemapper.eventTap = eventTap

        // イベントタップをランループに追加
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        // ランループを実行
        CFRunLoopRun()
    }

    // keyDown 時に、このキーをどう変換するか決める（nil = 変換しない）
    static func decideAction(keyCode: Int64, flags: CGEventFlags) -> RemapAction? {
        guard flags.contains(.maskControl) else { return nil }

        // Ctrl+M → Enter
        if keyCode == KeyCode.m {
            // 日本語IMEで変換候補ウィンドウが表示されている場合は、そのまま通す（変換確定に使用）
            if isJapaneseInputSourceActive() && isConversionCandidateWindowVisible() {
                return nil
            }
            return .enter
        }

        // Ctrl+; : @ / → Ctrl+矢印（Shift は引き継ぐ。Cmd / Option が併用されている場合は変換しない）
        if let arrow = arrowRemap[keyCode],
           flags.intersection([.maskCommand, .maskAlternate]).isEmpty {
            return .arrow(arrow, shift: flags.contains(.maskShift))
        }

        return nil
    }

    static func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
        // 処理が遅いなどの理由でタップが無効化された場合は再度有効化する
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let action: RemapAction?

        if type == .keyDown {
            let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isAutorepeat, let existing = activeActions[keyCode] {
                // キーリピート中は最初の判定を引き継ぐ
                action = existing
            } else {
                action = decideAction(keyCode: keyCode, flags: event.flags)
                activeActions[keyCode] = action
            }
        } else {
            // keyUp は keyDown 時の判定に従う（Ctrl を先に離しても対応が崩れないように）
            action = activeActions.removeValue(forKey: keyCode)
        }

        switch action {
        case nil:
            // その他のイベントはそのまま通す
            return Unmanaged.passUnretained(event)

        case .enter:
            // キーコードを Enter に書き換え、Control フラグを外す
            event.setIntegerValueField(.keyboardEventKeycode, value: KeyCode.returnKey)
            event.flags.remove(.maskControl)
            return Unmanaged.passUnretained(event)

        case .arrow(let arrowKey, let shift):
            // Mission Control のショートカットとして認識されるよう、HID レベルに Ctrl+矢印 を投入し直す。
            // 実際の矢印キーと同じく Fn / テンキーのフラグも付ける。
            let source = CGEventSource(stateID: .hidSystemState)
            if let newEvent = CGEvent(keyboardEventSource: source, virtualKey: arrowKey, keyDown: type == .keyDown) {
                var newFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
                if shift {
                    newFlags.insert(.maskShift)
                }
                newEvent.flags = newFlags
                newEvent.post(tap: .cghidEventTap)
            }
            // 元のキー（; : @ /）は捨てる
            return nil
        }
    }

    func stop() {
        if let eventTap = KeyRemapper.eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
    }
}

// メイン処理
print("=================================")
print("  Ctrl キーリマッピングツール")
print("=================================\n")

let remapper = KeyRemapper()

// シグナルハンドラを設定（Ctrl+Cで終了）
signal(SIGINT) { signal in
    print("\n\n終了します...")
    exit(0)
}

remapper.start()
