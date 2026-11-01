# Ctrl キーリマッピングツール

macOSで Ctrl+M を Enter に、Ctrl+; : @ / を Ctrl+矢印（Mission Control 操作）に変換するキーリマッピングツールです。
日本語入力中でも、変換候補が表示されていない場合は改行として動作します。

## 必要なもの

- macOS
- Xcode Command Line Tools

## インストール

### 1. Command Line Tools のインストール（未インストールの場合）

```bash
xcode-select --install
```

### 2. ビルド

```bash
chmod +x build.sh
./build.sh
```

## 使い方

### 実行

```bash
./KeyRemapper
```

### 初回実行時

1. アクセシビリティ権限のダイアログが表示されます
2. 「システム設定を開く」をクリック
3. **システム設定 → プライバシーとセキュリティ → アクセシビリティ**
4. ターミナル（または使用しているターミナルアプリ）をオンにする
5. 再度 `./KeyRemapper` を実行

### 終了

- `Ctrl+C` で終了します

## 動作

| 入力 | 出力 | 用途 |
|---|---|---|
| **Ctrl+M** | Enter | 改行・送信（日本語入力で変換候補の表示中は、そのまま通して変換確定に使う） |
| **Ctrl+;** | Ctrl+← | 左の操作スペースへ移動 |
| **Ctrl+:** | Ctrl+→ | 右の操作スペースへ移動 |
| **Ctrl+@** | Ctrl+↑ | Mission Control |
| **Ctrl+/** | Ctrl+↓ | アプリケーションウインドウ |

- HHKB の Fn レイヤーの矢印（Fn+; ← / Fn+: → / Fn+@ ↑ / Fn+/ ↓）と同じ配置なので、Fn を押さずに Mission Control を操作できます
- キーは物理位置で判定するため、US 配列では `;` `'` `[` `/` の位置になります
- Shift を併用すると Shift も引き継ぎます（例：Ctrl+Shift+@ → Ctrl+Shift+↑）
- Cmd / Option と同時に押した場合は変換しません
- 日本語入力（純正 IME）で入力中の Ctrl+;（半角カタカナ変換）と Ctrl+:（半角英字変換）は使えなくなります
- 他のキーは通常通り動作します

## 自動起動設定（オプション）

ログイン時に自動起動したい場合は、以下の手順で設定できます：

### launchd を使用する方法

1. 以下の内容で `~/Library/LaunchAgents/jp.co.kurotekko.taguchi.keyremapper.plist` を作成：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>jp.co.kurotekko.taguchi.keyremapper</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/KeyRemapper</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

2. パスを実際のファイルの場所に変更

3. 有効化：
```bash
launchctl load ~/Library/LaunchAgents/jp.co.kurotekko.taguchi.keyremapper.plist
```

無効化する場合：
```bash
launchctl unload ~/Library/LaunchAgents/jp.co.kurotekko.taguchi.keyremapper.plist
```

## トラブルシューティング

### 「アクセシビリティ権限が必要です」と表示される

→ システム設定でアクセシビリティ権限を許可してください

### ビルドエラーが出る

→ Command Line Tools がインストールされているか確認：
```bash
xcode-select -p
```

### キーが反応しない

1. プログラムが実行中か確認
2. アクセシビリティ権限が許可されているか確認
3. プログラムを再起動

## 注意事項

- このプログラムはシステムレベルでキーボード入力を監視します
- セキュリティ上、信頼できる環境でのみ使用してください
- 一部のアプリ（パスワード入力画面など）では動作しない場合があります

## ライセンス

MIT License

詳細は [LICENSE](LICENSE) ファイルを参照してください。

## 貢献

バグ報告や機能要望は、GitHubのIssuesでお願いします。
プルリクエストも歓迎します。

## 作者

Kurotekko Taguchi

## 一般公開について

このソフトウェアを一般公開する場合の推奨手順：

### GitHubに公開する

1. GitHubで新しいリポジトリを作成
2. ローカルでGitリポジトリを初期化：
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
   git push -u origin main
   ```

3. リリースを作成（オプション）：
   - GitHubのリリース機能を使用して、ビルド済みバイナリを配布

### Homebrewで配布する（オプション）

Homebrewで配布する場合は、以下のようなFormulaファイルを作成：

```ruby
class KeyRemapper < Formula
  desc "macOS key remapping tool: Ctrl+M → Enter"
  homepage "https://github.com/YOUR_USERNAME/YOUR_REPO_NAME"
  url "https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "YOUR_SHA256_HASH"
  license "MIT"

  depends_on :macos

  def install
    system "swiftc", "KeyRemapper.swift", "-o", "KeyRemapper"
    bin.install "KeyRemapper"
  end

  test do
    system "#{bin}/KeyRemapper", "--version"
  end
end
```

### 注意事項

- アクセシビリティ権限が必要なため、初回実行時にユーザーが手動で設定する必要があります
- セキュリティ上の理由から、バイナリを配布する場合は、コード署名を検討してください
- システムレベルのキーボード監視を行うため、ユーザーにセキュリティリスクを説明してください
