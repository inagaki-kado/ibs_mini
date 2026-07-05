# Cursor Agent 依頼テンプレート

Cursor チャットにそのまま貼って使う依頼文の雛形。

---

## 汎用修正

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
```

## 新機能追加

```
[ファイル名] に以下の機能を追加してください。

【追加機能】
[追加したい機能の詳細]

【制約】
- 既存の機能・UI・通信プロトコルを壊さないこと
- 新しいPeerJSメッセージが必要な場合は、新しいtypeを定義し既存typeは変更しないこと
- score.html側に受信処理が必要な場合は score.html も同時に修正すること
- iPhone/iPad対応（touch-action: manipulation）を維持すること
```

## score.html 修正

```
score.html を以下の通り修正してください。

【修正内容】
[修正内容]

【制約】
- UI/アニメーション/CSS変数名/関数名は指定がなければ変更しないこと
- PeerJS受信ハンドラ（REMOTE_CMD / SET_MATCH / SHOW_PREVIEW / HIDE_PREVIEW / SHOW_OVERLAY / HIDE_OVERLAY / SCROLL_OVERLAY / SET_BEYBLADE）を壊さないこと
- iPhone 17 Pro Max 横向き最適化を維持すること
- DSEG7 Classicフォントのパス（./font/DSEG7Classic-BoldItalic.ttf）を変更しないこと
- pro-mode / green-mode クラスの挙動を維持すること
```

## tournament_de.html 修正

```
tournament_de.html を以下の通り修正してください。

【修正内容】
[修正内容]

【制約】
- 標準DEトポロジー（start.gg / Challonge 系）を維持すること。プール合流型に変更しないこと
- `tournament.html` への DE モード統合は行わないこと
- localStorage キー `tbh_tournament_de` を維持すること
- `getBracketSnapshot()` の `format: 'double_elimination'` を維持すること
- 4色ブロック抽選フロー（`blockData` / ルーレット演出）を壊さないこと
- PeerJSメッセージタイプ・デザインテーマ・single-file制約は汎用修正テンプレートに準拠すること
```

## PeerJS 新メッセージ追加

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
```

---

## 選手紹介文生成（Claude Code 専用ワークフロー）

> **Cursorではなく Claude Code が実行する。** スプレッドシートを直接読み書きするため、ローカルxlsxは使わない。

### トリガー

- 「最新大会参加者の紹介文を生成して」
- 「{選手名}だけ紹介文を生成して」
- 「ケースA / B / C」で実行ケースを明示することもある

### Google Sheets API URL（認証不要・常に最新）

| シート | 用途 | URL |
|---|---|---|
| 🌐 Webデータ出力 | 選手名(A)・参加履歴(M)・紹介文(N)・全統計 | `https://docs.google.com/spreadsheets/d/1mJB7cH1I471WhFYqLh7B_IOECD6CuybuawFB89SN9Uc/gviz/tq?tqx=out:csv&sheet=%F0%9F%8C%90%20Web%E3%83%87%E3%83%BC%E3%82%BF%E5%87%BA%E5%8A%9B` |
| 📅 大会マスター | 大会名(B)・開催日(C) | `https://docs.google.com/spreadsheets/d/1mJB7cH1I471WhFYqLh7B_IOECD6CuybuawFB89SN9Uc/gviz/tq?tqx=out:csv&sheet=%F0%9F%93%85%20%E5%A4%A7%E4%BC%9A%E3%83%9E%E3%82%B9%E3%82%BF%E3%83%BC` |
| 【トラボカップ】チーム | チーム名・ブレーダー名（トラボCUP専用） | `https://docs.google.com/spreadsheets/d/1mJB7cH1I471WhFYqLh7B_IOECD6CuybuawFB89SN9Uc/gviz/tq?tqx=out:csv&sheet=%E3%80%90%E3%83%88%E3%83%A9%E3%83%9C%E3%82%AB%E3%83%83%E3%83%97%E3%80%91%E3%83%81%E3%83%BC%E3%83%A0` |

PowerShell 取得コマンド:
```powershell
$rows = (Invoke-WebRequest -Uri "<URL>" -UseBasicParsing).Content | ConvertFrom-Csv
```

### ケースA: 最新大会参加者・紹介文なしのみ生成（通常ケース）

1. 📅 大会マスター C列（開催日）の最大日付を特定
2. 🌐 Webデータ出力の「参加履歴」(M列)にその日付を含む選手を抽出
3. 「紹介文」(N列)が空の選手のみ対象（**既存文は絶対に触らない**）
4. 紹介文あり選手から上位15件を文体サンプルとして読む
5. 【トラボカップ】チームシートからチーム編成を取得
6. 対象選手の紹介文を Claude LLM で生成（下記ガイドライン準拠）
7. Apps Script を出力 → ユーザーがスプレッドシートで実行

### ケースB: 全員生成（ユーザー明示時のみ）

- Apps Script の `if (!cur)` 条件を除去して既存文も上書き対象にする
- 文体サンプルは現在のN列から30件取得して質を高める

### ケースC: 指定選手のみ生成

- 「{選手名}だけ生成して」でターゲットを絞る
- Apps Script にはその選手のみ記載
- 末尾スペース選手（例: 「ひかる 」）は名前をtrimせずそのまま

---

### 紹介文生成ガイドライン

**形式**: 3〜4文・**130〜165字**（1大会参加の新人は90〜120字でOK）  
**冒頭**: 必ず `{名前}は、` で始める  
**文末**: 「〜だ。」「〜する。」「〜した。」のみ（「〜です。」禁止）

#### 冒頭パターン（参加大会数と固有情報で選択）

| 経験値 | パターン例 |
|---|---|
| 特筆実績あり（公式大会優勝・称号） | `{実績}という{形容}を背負い、盤上でも〜` |
| 固有のベイ・スタイル確立 | `{ベイ名}を軸に組み立てた戦術で、相手の呼吸を乱す。` |
| 8大会以上 | `{N}大会の経験が、勝負のテンポを掴む武器になっている。` |
| 4〜7大会 | `{N}度の出場が自信に変わり、勝負の波に乗る手応えを掴んだ。` |
| 1〜3大会 | `白星の数こそ少ないが、ベイの回転に{情熱語}を燃やす新鋭だ。` |

#### トラボCUP文（最新大会がトラボCUPの場合は必須）

下記4パターンからランダム選択。`{チーム}` `{A}` `{B}` はシートから取得。

```
26年6月の「トラボCUP」に「{チーム}」として臨み、{A}、{B}と肩を並べて戦った。
26年6月の「トラボCUP」は「{チーム}」チームに所属し、{A}、{B}と連携し会場を沸かせた。
26年6月の「トラボCUP」で「{チーム}」チームの柱として{A}、{B}と共に戦線に立った。
26年6月の「トラボCUP」では「{チーム}」の一員として{A}、{B}と組み、チーム戦の熱を共にした。
```

> 次回大会が変わったら「26年6月の「トラボCUP」」部分を実際の大会名・日付に置き換える

#### 実績文（入賞履歴から最大2件・重複しない表現で）

```
優勝  : 〜で優勝を飾り、その名をベイブレード史に刻んだ。
優勝  : 〜で頂点に立ち、優勝の栄光を掴んだ。
準優勝: 〜で準優勝まで昇り詰め、頂点に一歩届かなかったが名勝負の数々を残した。
準優勝: 〜で準優勝を獲得し、次なる頂点を狙う実力を証明した。
3位  : 〜で3位入賞を記録し、実力の片鱗を示した。
4位  : 〜で4位入賞を果たし、表彰台の色を手にした。
番狂せ: 〜にて、格上の「{名前}」をBP差{N}万超差で撃破する番狂わせを演じた。
```

#### 禁止フレーズ

```
デビューから目覚ましい手応え / 次の大会が、新たな伝説 / 快挙を飾った
勝負の場で存在感を放つ / 次の一戦に向けて力を蓄えている
存在感を放つブレーダー / 上位25% / 75パーセンタイル
積み重ねた{ / 大会を越えて鍛え上げられた実戦派
```

#### 同名末尾スペース問題

選手名は **trim禁止**。`String(data[i][0])` をそのまま使う。  
「ひかる」と「ひかる 」は別人。チーム・チームメイトもそれぞれ別で確認する。

---

### Apps Script 出力テンプレート

Claude Code がこのテンプレートに `newBios` オブジェクトを埋めて出力する。

```javascript
function writeBios() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName('🌐 Webデータ出力');
  const data = sheet.getDataRange().getValues();

  // Claude Code 生成分 ── trim禁止・末尾スペースもそのまま
  const newBios = {
    "選手名1": "紹介文1",
    "選手名2": "紹介文2",
  };

  let written = 0, skipped = 0;
  for (let i = 1; i < data.length; i++) {
    const name = String(data[i][0]);   // A列: trim禁止
    if (!newBios.hasOwnProperty(name)) continue;
    const cur = data[i][13];           // N列 (0-indexed)
    if (!cur) {
      sheet.getRange(i + 1, 14).setValue(newBios[name]);
      written++;
    } else {
      skipped++;                       // 既存文は触らない
    }
  }
  SpreadsheetApp.getUi().alert(`完了: ${written}件書き込み / ${skipped}件スキップ（既存あり）`);
}
```

**実行手順**: スプレッドシート → 拡張機能 → Apps Script → 貼り付け → `writeBios` を実行

---

### 報告形式（Claude Code → ユーザー）

```
## 紹介文生成結果
- 対象大会: {大会名}（{日付}）
- 対象人数: {N}人（参加 {M}人中 紹介文なし {N}人）
- 生成した選手: {名前リスト}

## Apps Script（スプレッドシートに貼り付けて実行）
[スクリプト本文]
```
