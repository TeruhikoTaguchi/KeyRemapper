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

class KeyRemapper {
    var eventTap: CFMachPort?
    
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
        print("Ctrl+M → Enter に変換します")
        print("（変換候補表示中のみ変換確定として動作、それ以外は改行）")
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
        
        self.eventTap = eventTap
        
        // イベントタップをランループに追加
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        // ランループを実行
        CFRunLoopRun()
    }
    
    static func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
        // キーコードを取得
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // Mキー(keyCode: 46) + Controlキーの組み合わせをチェック
        if keyCode == 46 && flags.contains(.maskControl) {
            // 日本語入力ソース（IME）がアクティブな場合
            if isJapaneseInputSourceActive() {
                // 変換候補ウィンドウが表示されている場合は、そのまま通す（変換確定に使用）
                if isConversionCandidateWindowVisible() {
                    return Unmanaged.passRetained(event)
                }
                // 変換候補が表示されていない場合は、Enterキーに変換（改行）
            }
            
            // IMEが非アクティブ、または変換候補が表示されていない場合は、Enterキーに変換
            // Enterキー(keyCode: 36)のイベントを作成
            if let newEvent = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: type == .keyDown) {
                // Controlフラグを削除
                newEvent.flags = CGEventFlags(rawValue: flags.rawValue & ~CGEventFlags.maskControl.rawValue)
                return Unmanaged.passRetained(newEvent)
            }
        }
        
        // その他のイベントはそのまま通す
        return Unmanaged.passRetained(event)
    }
    
    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
    }
}

// メイン処理
print("=================================")
print("  Ctrl+M → Enter 変換ツール")
print("=================================\n")

let remapper = KeyRemapper()

// シグナルハンドラを設定（Ctrl+Cで終了）
signal(SIGINT) { signal in
    print("\n\n終了します...")
    exit(0)
}

remapper.start()
