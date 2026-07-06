# 板橋ベイブレード会 — 大会運営システム CLAUDE.md

> このファイルは **Claude Code** が読み込むプロジェクト仕様書。
> 全ての作業はここに書かれたルールに従うこと。

---

## ⚡ 作業方針（最優先ルール）

**ユーザーの依頼を受けたら、Claude Code が最初にルートを判定し、その方針で対応する。** 条件を満たす軽微修正は直接実施。それ以外は調査結果と実装ガイドを出力し、ユーザーが手動実装または claude.ai で継続する。

| 担当 | 内容 | 原則 |
|---|---|---|
| **Claude Code** | ルート判定・調査・原因特定・設計相談・**軽微修正（条件付き）**・実装ガイド生成 | 迷ったらルートB（実装ガイド出力）。巨大HTMLの全文Read禁止 |

### 2ルート制（着手前に必ず判定）

| ルート | 名称 | いつ |
|---|---|---|
| **A** | Claude直接修正 | 8項目チェックリスト全 ✅ かつ A禁止シグナルなし |
| **B** | Claude調査 → 実装ガイド出力 | 1つでも ❌、または原因不明 |

```
タスク発生
    │
    ├─ 8項目チェックリスト全✅ かつ A禁止シグナルなし？ ──Yes──▶ A: Claude直接修正
    │
    No
    │
    └─ B: Claude調査 → 実装ガイド出力（ユーザーが手動実装 or claude.ai で継続）
```

**迷ったら B。** A に無理に寄せない。

### 実装担当の判定（チェックリスト）

タスクごとに以下を確認し、**すべて ✅ かつ A禁止シグナルなし ならルートA（Claude Code が直接修正）**、**1つでも ❌ ならルートB（実装ガイドを出力）**。

| # | 条件 | 直接修正の要件 |
|---|---|---|
| 1 | 対象ファイル数 | **1ファイルのみ** |
| 2 | 変更行数 | **おおよそ 15行以内**（1関数・1ブロック内に収まる） |
| 3 | 原因の確度 | **調査済みで原因・修正方針が確定**している |
| 4 | 連携ファイル | `score.html` 等の**他ファイル修正が不要** |
| 5 | PeerJS | **既存 type の変更・削除なし**。新 type の追加なし |
| 6 | UI / CSS | **レイアウト・テーマ・クラス名の変更なし**（ロジック・文言・条件分岐のみ） |
| 7 | データ永続化 | `localStorage` キー・スキーマの変更なし |
| 8 | 調査コスト | 修正に必要な箇所は**既に Grep / 部分Read で把握済み**（全文Read不要） |

**即ルートB・実装ガイド出力（1つでも該当すれば）**

- 複数ファイル（例: 管理アプリ + `score.html`）
- 新機能・新タブ・新モーダルの追加
- DE トポロジー・ブラケット進行ロジックの変更
- UI デザイン・Tailwind クラス・カラーテーマの変更
- 原因が未確定、または修正方針に複数案がある

### 直接修正の追加シグナル（A禁止）

8項目が全 ✅ でも、**1つでも該当すればルートB** に切り替える。

| シグナル | 理由 |
|---|---|
| 同じバグを2回直した | 原因の見立てが浅い |
| 修正後の確認が複数画面必要 | 実機確認が複雑で見落としリスクが高い |
| `tournament.html` と `tournament_de.html` の同期が絡む | 見落としリスク |
| 関数名が3つ以上跨る | 15行以内でも影響範囲が広い |
| 「なぜそうなっているか」が説明できない | チェックリスト #3（原因確定）未充足 |

### Claude調査の上限（トークン節約）

| 項目 | 上限 |
|---|---|
| 部分Read | **合計200行以内**（複数回の累計） |
| 変更行数（ルートA） | **15行以内**（コメント除く） |
| ルートAの修正試行 | **1回のみ**（失敗・確認NGなら即ルートBへ） |

上限に達しそうな時点で調査を打ち切り、ルートBの実装ガイドを出力する。

### 実装ガイド必須5項目（ルートB）

手動実装・claude.ai での継続時の手戻りを防ぐため、以下を必ず含める。

1. **【判定】** なぜルートBか（チェックリスト何番が ❌ か）
2. **【原因】** 1〜2文で確定した原因
3. **【修正方針】** 関数名・行番号・変更前後のコード断片（5〜15行）
4. **【触らないもの】** 影響範囲の明示
5. **【確認手順】** Live Server での再現→修正確認手順

**ガイドの粒度**

| 規模 | 形式 |
|---|---|
| 1ファイル・50行以内の修正 | 上記5項目のみ（コンパクト） |
| UI変更・新機能 | 5項目 + 擬似コード or 差分イメージ |
| 複数ファイル | 5項目 + ファイル別の修正箇所リスト |
| DEロジック | Opus で設計メモ → Sonnet で実装ガイド化 |

**書かないもの（トークン節約）**: `CLAUDE.md` 制約の再掲、関係ないファイルの説明、複数案の長文比較（採用案1つに絞る。別案は補足1行まで）。

### Claude Code が守ること

1. 着手前に **2ルート制** で判定し、冒頭で一行宣言する（例: `→ ルートA 直接修正（8/8 条件充足）` / `→ ルートB 実装ガイド出力（条件3未充足）`）
2. 調査は **Grep + 部分Read** のみ。巨大HTML（3000行超）の全文Readは禁止。部分Readは累計200行以内
3. **ルートA** は修正1回打ち切り。確認NGなら再調査せずルートBへ
4. **ルートA 直接修正** 後は変更内容・対象箇所・確認手順を簡潔に報告する
5. **ルートB 実装ガイド出力** は必須5項目を含める（規模に応じてコンパクト／詳細）
6. **1タスク1セッション**。調査と別件の設計を混ぜない。ユーザーが「調査だけ」と指定した場合は実装ガイドのみ出力し修正しない

### Claude Code の標準出力フォーマット

#### A. ルートA — 直接修正した場合

```
## 判定
→ ルートA 直接修正（チェックリスト X/8 条件充足）

## 変更内容
- ファイル: [ファイル名]
- 箇所: [関数名] Lxxx 付近
- 内容: [1〜2文]

## 確認手順
[Live Server でのテスト方法]
```

#### B. ルートB — 実装ガイドを出力する場合

```
## 判定
→ ルートB 実装ガイド出力（条件[N]未充足: [理由]）

## 調査結果
- 原因: [1〜2文]
- 対象: [ファイル名] の [関数名]（おおよそ Lxxx 付近）

## 実装ガイド
[必須5項目を含む実装手順。規模に応じてコンパクト／詳細]

## 補足
- 影響範囲 / 触らないもの:
- 確認手順: Live Server で [何を確認するか]
```

### 例外

- **ドキュメント**（`CLAUDE.md` / `REFERENCE.md` / `PROMPT_TEMPLATES.md`）はユーザーが明示した場合、チェックリストに関わらず Claude Code が直接編集してよい

---

## モデル切替ルール（Claude Code）

トークンを効率的に使うため、作業内容に応じて `/model` コマンドでモデルを切り替える。

| Tier | モデル | 料金（入力/出力 per 1M） | 対象タスク |
|------|--------|--------------------------|------------|
| **1** | `claude-haiku-4-5` | $1 / $5 | 単純検索・Grep確認・行番号特定・場所探し |
| **2** | `claude-sonnet-4-6` | $3 / $15 | 調査・原因分析・プロンプト生成・軽微修正・設計相談 ← **デフォルト** |
| **3** | `claude-opus-4-8` | $5 / $25 | 複雑なアーキテクチャ判断・ロジック設計・大規模デバッグ |

### 各 Tier の判断基準

**Tier 1（Haiku）** — 「答えを探すだけ」のとき
- 「〇〇という関数はどこにある？」「〜を含む行を探して」
- ファイル一覧・行数確認などの単純検索

**Tier 2（Sonnet）** — 「答えを判断する」とき ← セッション開始時のデフォルト
- チェックリストに沿った調査・原因特定
- 実装ガイド生成・軽微修正（15行以内）
- 設計の壁打ち・相談

**Tier 3（Opus）** — 「答えを設計する」とき
- DE ブラケット・ブロック戦進行ロジックの設計
- PeerJS メッセージ拡張の影響範囲分析（複数ファイルにまたがる場合）
- 新機能のアーキテクチャ設計（実装前の整理）

### フェーズ別モデル切替（実運用）

| フェーズ | モデル |
|---|---|
| 場所探し・行番号特定 | **Haiku**（Tier 1） |
| チェックリスト判定・軽微修正・プロンプト生成 | **Sonnet**（Tier 2・デフォルト） |
| DE設計・PeerJS影響分析 | **Opus**（Tier 3） |

**ルール**: Opus は設計が終わったら即 Sonnet に戻す。Opus で実装までやらない。プロンプト生成は Sonnet で行う。

### 切替コマンド

```
/model claude-haiku-4-5   # Tier 1
/model claude-sonnet-4-6  # Tier 2（デフォルト）
/model claude-opus-4-8    # Tier 3
```

---

---

## プロジェクト概要

ベイブレードX大会をリアルタイム運営するための**単一HTMLファイル群**。
- ビルドツール不要
- 全CSS・JSをHTMLに埋め込んだ**完全自己完結型**（single-file制約）
- 開発者: 稲垣 (handle: INASSY / Inagaki Yammy)
- クラブ: 板橋ベイブレード会（Itabashi Beyblade Club）
- X: @yamizaki

---

## ファイル一覧

| ファイル | 役割 | アクセントカラー |
|---|---|---|
| `tournament.html` | メイン大会管理（ブロック戦シングルエリミ・ベイ登録・参加者管理） | 青 `#0ea5e9` |
| `tournament_de.html` | ダブルエリミネーション大会管理（標準DE・4色抽選・GFリセット） | 青 `#0ea5e9` |
| `tournament_evo.html` | EVO JAPAN 2026向け拡張版（当日参加抽選タブ付き） | 青 `#0ea5e9` |
| `tag.html` | タッグリーグ管理（スイス＋決勝T） | ピンク `#ec4899` |
| `souatari.html` | 総当たりリーグ管理 | 青 `#0ea5e9` |
| `freebattle.html` | フリー対戦管理 | オレンジ `#fb923c` |
| `block.html` | ブロック戦子機（スタジアム担当者用） | 緑 `#22c55e` |
+ | `tournament_de_sub.html` | tournament_de.htmlのLBスタッフ管理子機（4桁コード接続） | 青 `#0ea5e9` |
| `score.html` | OBS用HUDディスプレイ（受信専用・Ver.34） | — |
+ | `cx_parts_chart.html` | CXパーツ参照チャート（tournament.htmlからiframeモーダル表示） | — |
| `player_stats.html` | ブレーダー統計ポータル（Google Sheets連携） | 緑 `#00ff88` |
- | `lottery.html` | 抽選アプリ | — |
| `spectator.html` | 観客向け表示 | — |
| `index.html` | 公開用クラブサイト | — |
| `showcase.html` | 他クラブへのシステム紹介用プレゼンポータル | — |
| `parts.csv` | ベイブレードパーツマスターデータ | — |

---

## 通信トポロジー

```
[tournament.html]  ─┐
[tournament_de.html]─┤
[tournament_evo.html]─┤
[tag.html]         ─┤  PeerJS v1.5.2  →  [score.html] (OBS Browser Source)
[souatari.html]    ─┤
[freebattle.html]  ─┤
[block.html]       ─┘  (独自の BLOCK_INIT も送信)
```

- **送信側（管理アプリ）**: `conn.send(message)` で送信
- **受信側（score.html）**: `peer.on('connection')` → `conn.on('data')` でハンドリング
- 接続コード: 4桁数字をUIで手入力して `Peer(peerId)` でマッチング

---

## 技術スタック

### 全管理アプリ共通
- **Tailwind CSS** (CDN) — `tailwind.config` でカスタムカラー定義
- **PeerJS v1.5.2** (CDN) — `https://unpkg.com/peerjs@1.5.2/dist/peerjs.min.js`
- **Orbitron** (Google Fonts) — 英数字UI用
- **Noto Sans JP** (Google Fonts) — 日本語UI用

### score.html 専用
- **Chakra Petch** (Google Fonts) — スコアボード用
- **DSEG7 Classic** — `./font/DSEG7Classic-BoldItalic.ttf`（7セグスコア表示）
- **FontAwesome 6.5.0** (CDN)

### player_stats.html 専用
- **Rajdhani** (Google Fonts)
- **Chart.js 4.4.1** (CDN) — 統計グラフ
- **FontAwesome 6.5.0** (CDN)

### tag.html 専用
- **JSZip 3.10.1** (CDN) — データエクスポート

---

## デザインテーマ（サイバーダーク）

全管理アプリで統一する。変更禁止。

| Tailwindキー | カラーコード | 用途 |
|---|---|---|
| `cyber-bg` | `#0a0e17` | ページ背景 |
| `cyber-dark` | `#111827` | カード・ヘッダー背景 |
| `cyber-blue` | `#0ea5e9` | メインアクセント |
| `cyber-green` | `#22c55e` | 成功・勝利 |
| `cyber-pink` | `#ec4899` | タッグ戦アクセント・警告 |
| `cyber-orange` | `#ffaa00` | オレンジアクセント |
| `cyber-red` | `#ff0055` | XTREME・エラー |
| `cyber-red-orange` | `#ff4500` | BURST |
| `cyber-text` | `#e2e8f0` | 通常テキスト |
| `cyber-table-border` | `#1f2937` | 罫線・区切り |

- `tournament.html` を**UIマスター**とし、他アプリのボタン配置・ヘッダー構成をそれに準拠させる
- 英数字フォント: **Orbitron** / 日本語フォント: **Noto Sans JP**

---

## ⚠️ 絶対に守るルール（変更禁止）

### 1. single-file アーキテクチャ
- CSS・JSは全てHTMLに埋め込む
- 外部ファイルへの分割禁止（`parts.csv` と `./font/` ファイルを除く）

### 2. PeerJS メッセージタイプ保護
以下の `type` 値は**変更・削除禁止**。新機能は新しい `type` 値を定義すること。

| type | 用途 |
|---|---|
| `REMOTE_CMD` | スコア加算・リセット・カメラ反転等のシステムコマンド |
| `SET_MATCH` | プレイヤー名・戦績・大会名のセット |
| `SHOW_PREVIEW` | 次戦予告オーバーレイ表示 |
| `HIDE_PREVIEW` | 次戦予告オーバーレイ非表示 |
| `NEXT_BATTLE_CALL` | 旧互換（削除禁止） |
| `SHOW_OVERLAY` | 大会結果等の全画面HTML表示 |
| `HIDE_OVERLAY` | 全画面オーバーレイ非表示 |
| `SCROLL_OVERLAY` | オーバーレイスクロール |
| `SET_BEYBLADE` | 使用ベイブレード名の表示反映 |
| `BLOCK_INIT` | ブロック子機への一括初期化 |
| `SHOW_SCORE_VIEW` | 次戦予告・休憩・オーバーレイを全て非表示にしてスコア画面へ戻す |
| `BREAK_START` | 休憩中オーバーレイ表示（`p1`/`p2`/`logoDataUrl`/`previewBackground`/`logoSrc`/`showLogo` を含む） |
| `BREAK_END` | 休憩中オーバーレイ非表示 |

- `SHOW_OVERLAY` を送信した場合、モーダルを閉じる時に必ず `HIDE_OVERLAY` も送信すること

### 3. iOS対応
- 全ボタンに `touch-action: manipulation` を付与（iOS遅延対策）
- `handleTouch` 等のタップ遅延対策ロジックを維持すること
- `maximum-scale=1.0, user-scalable=no` のviewport設定を維持

### 4. score.html 保護
- `./font/DSEG7Classic-BoldItalic.ttf` のパスを変更しないこと
- `body.pro-mode` / `body.green-mode` クラスの挙動を維持すること
- iPhone 17 Pro Max 横向き最適化を維持すること

### 5. file:// 制限
- `fetch('parts.csv')` はローカルの `file://` では動作しない
- 開発時は **Live Server**（VS Code 拡張等）でサーバー経由アクセスすること

---

## PeerJS REMOTE_CMD コマンド一覧

詳細コマンドリスト・score.html HUD仕様・ベイブレードパーツ登録仕様 → [`REFERENCE.md`](REFERENCE.md)

---

## BP（ベイパワー）計算ロジック

- スケール: **10,000ベース**（Eloライク）
- 勝者: 最小 **+200** / 最大可変
- 敗者: 最大 **−150**
- フロア: **10,000**（下限固定）
- 勝敗別に異なるパスで計算

---

## tournament.html 固有仕様

- **UIマスター**。他アプリのUI基準となる
- `localStorage` で大会状態を保存・再開（キー: `tbh_tournament`）
- **ブロック戦シングルエリミ**: A〜D 各ブロック → 準決勝 → 決勝 + 3位決定戦
- Bay Checkフォト撮影機能
- CSV出力 / テキスト出力（ベイ名のみ）
- `cx_parts_chart.html` をiframeでモーダル表示（`openCxChart()` / `closeCxChart()`）
- カスタムalert/confirm: `showAlert()` / `showConfirm()`（ネイティブダイアログ不使用）
- リモートコントロールモーダル: score.htmlへの各種コマンド送信パネル

---

## tournament_de.html 固有仕様

`tournament.html` をフォークした**ダブルエリミネーション専用**アプリ。参加者管理・4色ブロック抽選・ベイ登録・PeerJS連携のシェルは `tournament.html` と共通。トーナメント進行ロジックのみ差し替え。

### 大会形式

- **トポロジー**: start.gg / Challonge 系の標準DE（プール合流型ではない）
- **ブラケット構成**: `winnersBracket`（WB）+ `losersBracket`（LB）+ `grandFinal` + `grandFinalReset`（条件付き）+ `lbThirdPlace`
- **人数**: 任意人数 + BYE（`P = 2^⌈log₂N⌉` にパディング）
- **2人大会**: LB/GF なし。WB 1試合で決着（特例）

### 抽選 → シード

- 大会前の **4色ブロック抽選**（ルーレット演出・`getFairPositions`）は `tournament.html` と同一
- `startTournament()` 時に `blockData` をポジション順（A-1, B-1, C-1, D-1, A-2, …）でフラット化
- 標準トーナメントシード配置（1 vs P, 2 vs P-1 …）で WB 初戦を生成

### グランドファイナル・順位

| 順位 | 決定方法 |
|---|---|
| 1位 | GF（または GF リセット戦）勝者 |
| 2位 | GF 敗者 |
| 3位 | `lbThirdPlace` 勝者（LB内・8人以上で LB 準決勝相当の敗者同士） |
| 4位 | `lbThirdPlace` 敗者 |

- **ブレケットリセット**: GF で LB 側（p2）が勝利 → `grandFinalReset` を生成。リセット戦の勝者が大会優勝
- **大会終了条件**: `isTournamentFinished()` — GF（+リセット戦）確定 かつ 3位決定戦確定（8人以上時）

### 主要関数・Google Sheets スキーマ

詳細 → [`REFERENCE.md`](REFERENCE.md)

### 保存・UI

- `localStorage` キー: **`tbh_tournament_de`**（`tournament.html` の `tbh_tournament` と分離）
- トーナメントタブ: **WINNERS** / **LOSERS** サブタブ + 下部 **GRAND FINAL** エリア
- 手動入替: **WT R1 のみ**（`winnersBracket[0]`）
- TVモード: `buildTvTournamentHtml()` は WB/LB 2カラム + FINAL STAGE

### 保守方針

- **新規DE機能は `tournament_de.html` に追加**。`tournament.html` に DE モードを統合しない
- `tournament.html` の共通機能（ベイ登録・PeerJS等）を改修した場合、必要に応じて `tournament_de.html` へ手動同期
- ブロック戦＋子機連携が必要な場合は `tournament_main.html` を使用（DE 非対応）

### 未実装（バックログ参照）

- LB 落下時の未対戦優先ヒューリスティック（`playedPairs` + インターリーブ）

---

## block.html 固有仕様

- **3人チーム戦**: 先鋒・次鋒・大将の3ポジション
- **生存ルール（サバイバル）**: 勝者は次の相手と連続対戦。負けた側のみ交代
- 3本先取でチーム勝利
- 親機（tournament.html等）から `BLOCK_INIT` で一括初期化
- score.htmlとは別に独立したPeerJS接続を持つ

---

## player_stats.html 固有仕様

- **Google Sheets CSV**（公開URL）から `fetch` で取得
- `🌀 ベイ集計` シート: お気に入りベイブレード上位5件
- 用語: **BLADER / ブレーダー**（「PLAYER」は使わない）
- 受賞歴は日付降順ソート
- ライバルをクリックするとジャンプ検索

---

## 外部サービス連携

| サービス | 用途 |
|---|---|
| **Google Sheets** | player_stats・BP計算・イベント履歴のデータバックエンド（CSV公開URL経由）|
| **PeerJS v1.5.2** | アプリ間リアルタイム通信 |
| **OBS** | 配信。score.htmlをブラウザソースとして使用 |
| **Tonamel** | 事前参加登録・公開イベントページのみ（API連携なし） |
| **allorigins.win** | CORSプロキシ（OGP画像取得用） |
| **Live Server（VS Code 等）** | ローカル開発（CSV fetch対応） |
| **X (Twitter) @yamizaki** | クラブ公式アカウント |

---

## 開発ワークフロー

### 基本方針：Claude がルート判定、軽微修正は直接・それ以外は実装ガイド出力

| フェーズ | 担当 | 内容 |
|---|---|---|
| ルート判定 | **Claude Code** | 2ルート制（A/B）を冒頭で宣言 |
| 調査・設計 | **Claude Code** | 原因特定、影響範囲、修正方針の整理 |
| 軽微修正（ルートA） | **Claude Code** | 8/8 + A禁止シグナルなし・15行以内 |
| 中〜大規模実装（ルートB） | **ユーザー手動 or claude.ai** | Claude の実装ガイドを元に実装 |
| 設計相談（任意） | **claude.ai** | 仕様の壁打ち |

### ケース別フロー

| ケース | ルート | フロー |
|---|---|---|
| 修正箇所が明確・小さい | **A** | Claude がチェックリスト判定 → 充足なら直接修正 |
| チェックリスト未充足・原因不明 | **B** | Claude 調査 → 実装ガイド（必須5項目）→ ユーザー手動実装 |
| 仕様確定済みの大きい作業 | **B** | Claude が実装ガイド出力 → ユーザー手動実装 |
| DE・PeerJS・大会当日バグ | **B** | Claude 調査（Sonnet）→ 必要なら Opus 設計 → 実装ガイド出力 |
| 仕様が固まっていない | — | claude.ai で設計 → Claude 調査 → 実装ガイド出力 |

### エスカレーション

```
ルートA 直接修正 → 確認NG → ルートB（再調査・実装ガイド出力）→ ユーザー手動実装
ルートB → 手動実装 → 確認NG → Claude 再調査（前回の仮説破棄を明記）
2回失敗 → Opus で設計見直し or ユーザー判断
```

### ケース別クイックリファレンス

| タスク | ルート | Claude モデル |
|---|---|---|
| 文言・typo 修正 | A | Sonnet |
| `if` 条件のバグ1箇所 | A | Sonnet |
| score.html に表示が出ない（原因不明） | B | Sonnet |
| 新タブ追加 | B | Sonnet → 実装ガイド出力 |
| DE の LB 進行バグ | B | Opus 設計 → Sonnet 実装ガイド出力 |
| 「この関数どこ？」（修正なし） | — | Haiku |
| 大会当日の緊急バグ | B | Sonnet 優先 |
| 紹介文生成（最新大会・個別・全員） | — | `PROMPT_TEMPLATES.md`「選手紹介文生成」セクション参照 |

### ユーザー（稲垣）の依頼テンプレート

**Claude Code への依頼（日常用・ルール省略可）**

Claude Code は本ファイルのルールに従い、**依頼文にルールがなくても**着手前にルートを判定する。以下は明示したいときのテンプレート。

```
[現象 or やりたいこと] について対応してください。
```

省略形で十分。Claude が自動で 2ルート判定・チェックリスト・必須5項目を適用する。

**Claude Code への依頼（ルール明示版）**

```
[現象 or やりたいこと] について対応してください。

【ルール】
- 2ルート制で A/B を冒頭宣言
- Grep + 部分Read のみ（200行累計上限）
- 8/8 かつ A禁止シグナルなしなら直接修正、それ以外は実装ガイド出力（必須5項目）
- 直接修正は1回のみ。ダメなら実装ガイドへ
- 「調査だけ」と書いた場合は修正せず実装ガイドのみ
```

### 作業手順

1. タスク発生 → **Claude Code** に依頼（ルール省略可。Claude が自動判定）
2. ルートA で直接修正 → Live Server で確認。問題あればルートB へ
3. ルートB で実装ガイド出力 → ガイドを元に**ユーザーが手動実装**、または **claude.ai** で継続
4. 実装後の確認結果を Claude に返すと、再調査の入力になる

### バックアップ

`CLAUDE.md` 等の重要ファイルを変更する前に、同ディレクトリへ `.backup` コピーを取ること。

---

## 実装ガイドテンプレート

→ [`PROMPT_TEMPLATES.md`](PROMPT_TEMPLATES.md)（実装ガイドの詳細フォーマット参照）

---

## 未実装・検討中（バックログ）

| 機能 | 対象ファイル | ステータス |
|---|---|---|
| DE: LB未対戦優先落下順 | `tournament_de.html` | 📋 検討中 |
| 決まり手トラッキング | `tournament.html`, `player_stats.html`, Google Sheets | 🔍 調査中 |
| 決まり手統計（フィニッシュタイプ別・ベイブレード別勝率） | `player_stats.html` | 🔍 調査中 |
| PeerJS URL parameter自動接続（`score.html?peer=1234`） | `score.html` | ✅ 実装済 |
| PeerJS 自動再接続ロジック | 全管理アプリ | 📋 検討中 |
| BX-09 Battle Pass Bluetooth連携 | — | 🔍 Bluefy経由で調査中 |
| クラブ間リーグ提案 | `showcase.html` | 📋 企画中 |
