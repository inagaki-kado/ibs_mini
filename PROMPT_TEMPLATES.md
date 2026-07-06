# 板橋ベイブレード会 — PROMPT_TEMPLATES.md

> Cursor 等のAIコーディングエージェントに手動で依頼する際のプロンプトテンプレート集。
> `[...]` の部分を実際の内容に置き換えて使用する。
> Claude Code への依頼テンプレートは CLAUDE.md 側（ルートA/B判定用）を参照。

---

## 🔧 汎用修正プロンプト

```
以下のルールに従って [ファイル名] を修正してください。

【修正内容】
[修正したい内容を具体的に記述]

【制約】
- 修正は指定箇所のみに限定し、他の機能・UI・アニメーション・変数名には一切変更を加えないこと
- PeerJSのメッセージタイプ（REMOTE_CMD / SET_MATCH / SHOW_PREVIEW / HIDE_PREVIEW / SHOW_OVERLAY / HIDE_OVERLAY / SCROLL_OVERLAY / SET_BEYBLADE / BLOCK_INIT）は変更・削除禁止
- ボタンには touch-action: manipulation を維持すること
- デザインテーマ（背景 #0a0e17、アクセントカラー #0ea5e9/#ec4899/#22c55e）を維持すること
- single-file HTMLアーキテクチャを維持すること（CSS・JSをHTMLから分離しないこと）
- 変更後はファイル全量を提示し、冒頭に変更点のサマリーを記載すること
```

---

## 🆕 新機能追加プロンプト

```
[ファイル名] に以下の機能を追加してください。

【追加機能】
[追加したい機能の詳細]

【制約】
- 既存の機能・UI・通信プロトコルを壊さないこと
- 新しいPeerJSメッセージが必要な場合は、新しいtypeを定義し既存typeは変更しないこと
- score.html側に受信処理が必要な場合は score.html も同時に修正すること
- tournament.html のUIをマスターとして、同等の新機能はtag.html/souatari.html/freebattle.htmlにも同様に反映すること（指示がある場合）
- iPhone/iPad対応（touch-action: manipulation、handleTouch）を維持すること
- 変更後はファイル全量を提示し、冒頭に変更点のサマリーを記載すること
```

---

## 🎨 score.html 修正プロンプト

```
score.html を以下の通り修正してください。

【修正内容】
[修正内容]

【制約】
- UI/アニメーション/CSS変数名/関数名は指定がなければ変更しないこと
- PeerJS受信ハンドラ（REMOTE_CMD / SET_MATCH / SHOW_PREVIEW / HIDE_PREVIEW / SHOW_OVERLAY / HIDE_OVERLAY / SCROLL_OVERLAY / SET_BEYBLADE / SHOW_SCORE_VIEW / BREAK_START / BREAK_END）を壊さないこと
- iPhone 17 Pro Max 横向き最適化を維持すること
- DSEG7 Classic フォントのパス（./font/DSEG7Classic-BoldItalic.ttf）を変更しないこと
- pro-mode / green-mode クラスの挙動を維持すること
- 変更後はファイル全量を提示し、冒頭に変更点のサマリーを記載すること
```

---

## 📊 player_stats.html 修正プロンプト

```
player_stats.html を以下の通り修正してください。

【修正内容】
[修正内容]

【制約】
- 「PLAYER」という表記を使わず「BLADER / ブレーダー」を使うこと
- Google Sheets CSV取得のURLや構造を壊さないこと
- サイバーネオンUIテーマ（--bg: #04070f、--neon-green: #00ff88等のCSS変数）を維持すること
- Chart.jsによるグラフ描画を維持すること
- 変更後はファイル全量を提示し、冒頭に変更点のサマリーを記載すること
```

---

## 🔗 PeerJS 新メッセージ追加プロンプト

```
[送信側ファイル名] と score.html に新しいPeerJSメッセージタイプ「[TYPE_NAME]」を追加してください。

【送信データ仕様】
[フィールド名とその型・意味を記述]

【score.html側の処理】
[受信時の表示・動作を記述]

【制約】
- 既存のメッセージタイプは変更・削除しないこと
- score.html の conn.on('data') ハンドラ内に新しい else if ブロックを追加すること
- 送信側は conn.open チェック後に送信すること
- 変更後はファイル全量を提示し、冒頭に変更点のサマリーを記載すること
```

---

## 👤 選手紹介文生成プロンプト

```
[player_stats.html / Google Sheets のデータ] を元に、以下の対象の紹介文を生成してください。

【対象】
[最新大会の参加者全員 / 個別選手名 / 全ブレーダー]

【文体】
- 用語は「BLADER / ブレーダー」を使用（「PLAYER」は使わない）
- [その他の文体指定があれば記述]
```
