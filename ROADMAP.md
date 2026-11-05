# NoteMap Roadmap

最終更新: 2026-11-05

## 現在地

```text
[完了] リポジトリ・README確認
[完了] 実メモの明示リンクグラフを実機で検証
[完了] boco mothership に Ollama と埋め込みモデルを導入
[完了] boco-mothership.local 経由でMacからGPU埋め込みを実行
[完了] アプリのOllama接続先を設定可能にする
   ↓
[次]   HeightmapでリモートGPUの埋め込みを実機検証
```

## 検証・開発の流れ

```text
SettingsでリモートOllamaの接続先・埋め込みモデルを保存
   ↓
Heightmapで初回の全ノート埋め込みを実行・確認
   ↓
変更メモだけを非同期で埋め込む仕組みを設計・実装
   ↓
意味的な関係線と説明UIを設計・実装する
```

## 確認済み

- Xcode 26.6 でプロジェクトのビルドに成功。
- フルディスクアクセスの許可後、Apple Notes のデータベースを read-only で開けた。
- 561件のメモを検出（現行フィルタでは557件）。
- 実メモからグラフノード557件、明示リンク287本、本文スニペット52件を取得。
- グラフHTMLの生成完了（2,754,597文字）。アプリは実行を継続中。
- `ProtobufReader` に安全な整数変換と境界検査を追加し、範囲外の長さ候補をスキップするよう修正。
- boco mothership（RTX 2070 SUPER・8GB VRAM）へOllama 0.40.14を導入。
- 多言語埋め込みモデル `qwen3-embedding:4b`（約2.5GB）を導入し、2,560次元のGPU埋め込みを確認。
- Ollamaは `boco-mothership.local:11434` で自宅LANから利用できる。Windows Defenderの許可範囲は `192.168.151.0/24` に限定。
- アプリのSettingsからOllamaサーバーを変更でき、モデル一覧・モデル取得・埋め込み・ラベル生成が同じ接続先を使用する。

## 実機確認済み

- 日本語本文を画面上で表示できる。
- 明示リンクをグラフ上で表示できる。
- グラフから元のApple Notesを開ける。

## 保留する改善候補

日本語本文とリンク解析の精度改善は、具体的な取りこぼし・誤検出が確認された時点で着手する。現時点では、基本操作を妨げる不具合としては扱わない。

## 次の作業

Settingsで `http://boco-mothership.local:11434` と `qwen3-embedding:4b` を保存し、Heightmapの実メモ埋め込みを確認する。

## 外出先での利用

`.local` は自宅LAN内だけで有効。外出先のMacや将来のiPhoneから同じ推論先を使う場合は、Ollamaを公開せず、TailscaleなどのプライベートVPNと固定DNS名を追加する。
