# 板橋ベイブレード会 — REFERENCE.md

> CLAUDE.md から参照される詳細リファレンス。
> ファイル一覧・技術スタック・各アプリ固有仕様・BP計算・外部サービス連携は **CLAUDE.md が正**。
> ここには CLAUDE.md に書ききれない詳細（コマンド一覧・パーツ仕様・HUD仕様・イベントレポート仕様）のみを置く。

---

## 1. PeerJS REMOTE_CMD コマンド一覧

`REMOTE_CMD` メッセージの `cmd` フィールドに指定する値の一覧。

| cmd値 | 動作 |
|---|---|
| `P1_X` / `P2_X` | P1/P2 に XTREME フィニッシュ（+3点） |
| `P1_B` / `P2_B` | P1/P2 に BURST フィニッシュ（+2点） |
| `P1_O` / `P2_O` | P1/P2 に OVER フィニッシュ（+2点） |
| `P1_S` / `P2_S` | P1/P2 に SPIN フィニッシュ（+1点） |
| `P1_MINUS` / `P1_PLUS` | P1 のスコアを1点減算/加算（`winScoreLimit` で上限） |
| `P2_MINUS` / `P2_PLUS` | P2 のスコアを1点減算/加算（`winScoreLimit` で上限） |
| `SYS_RESET` | スコアリセット（旧互換で小文字 `reset` も同一動作。`tag.html` 等が送信） |
| `SYS_RELOAD` | score.html を `location.reload()` |
| `P1_WIN` / `P2_WIN` | P1/P2 の試合勝利を確定 |
| `SYS_HIDE_WIN` | 勝利表示の非表示 |
| `SYS_WIN_MODE_2` | 勝利ポイントモードの切替 |
| `SYS_TOGGLE_WINPOINT` | 勝利ポイント表示のON/OFF切替 |
| `SYS_PRO` | PRO MODE 切替（UIボタン非表示・配信用クリーンモード） |
| `SYS_STATS` | 戦績表示切替 |
| `SYS_CAM` | カメラ180°反転 |
| `SYS_SWAP` | P1/P2 入替（score.html は内部変数を物理入替。加点コマンドのside反転は不要） |
| `SYS_HUD` | HUD全体の表示/非表示（`body.hud-hidden`） |
| `CALL` | 試合コール（3-2-1-GO!-SHOOT!）の開始/キャンセルをトグル |
| `TIMER` | タイマーの開始/停止トグル |
| `REPLAY_TOGGLE` | リプレイモードの切替 |
| `REPLAY_PLAY` | リプレイ再生/一時停止 |
| `REPLAY_SLOW` | リプレイ再生速度の切替（スロー段階サイクル） |
| `REPLAY_FRAME_FWD` / `REPLAY_FRAME_REV` | リプレイをコマ送り/コマ戻し |
| `REPLAY_LOOP` | リプレイのループ再生ON/OFF |
| `REPLAY_LOOP_LEN` | リプレイのループ長を切替 |
| `REPLAY_ZOOM` | リプレイのズーム表示切替 |
| `REPLAY_SEEK_FWD` / `REPLAY_SEEK_REV` | リプレイをシーク送り/シーク戻し |
| `REPLAY_REV` | リプレイの巻き戻し再生 |
| `REPLAY_LATEST` | リプレイを最新（バッファ末尾）にシーク |

> 確認済み: 上記は `score.html` の `executeCommand()` / `applyGameplayScore()` を Grep して洗い出した全 `cmd` 値。score.html に新しい `cmd` 値を追加した場合は、このテーブルに追記すること。

---

## 2. ベイブレードパーツ登録仕様

### parts.csv
- マスターデータ。`window.addEventListener('DOMContentLoaded')` でロード
- `fetch('parts.csv')` はローカル `file://` では動作しないため、**Live Server** 等でサーバー経由アクセスすること

### パーツIDプリフィックス

| プリフィックス | パーツ種別 |
|---|---|
| `BX` | BXブレード |
| `UX` | UXブレード |
| `RC` | ロックチップ（CXライン専用） |
| `CX` | メインブレード |
| `AB` | アシストブレード |
| `MB` | メタルブレード（CX EXライン） |
| `OB` | オーバーブレード（CX EXライン） |
| `RA` | ラチェット |
| `BT` | ビット |

### 登録フロー

```
BX/UXライン:   ブレード(BX/UX) → ラチェット(RA) → ビット(BT)
CXライン:      ロックチップ(RC) → メインブレード(CX) → アシスト(AB) → ラチェット(RA) → ビット(BT)
CX(EX)ライン:  ロックチップ(RC) → メタル(MB) → オーバー(OB) → アシスト(AB) → ラチェット(RA) → ビット(BT)
```

- パーツ結合時は**記号を使わず**名前を詰めて1つの文字列にする（例: `ドランバスターRatchet3-60F`）

---

## 3. score.html HUD仕様

### ランク表示（ITABASHIX-TOWER方式）

| 範囲 | クラス | カラー |
|---|---|---|
| 01F〜39F | `rank-white` | 白 `#FFFFFF` |
| 40F〜59F | `rank-blue` | サイバーブルー `#0EA5E9` |
| 60F〜79F | `rank-green` | マトリックスグリーン `#00FF41` |
| 80F〜89F | `rank-purple` | ネオンパープル `#A855F7` |
| 90F〜99F | `rank-red` | クリムゾンレッド `#EF4444` |
| XF | `rank-gold` | シャイニングゴールド `#F59E0B`（gold-pulseアニメーション付き） |

### フィニッシュタイプ・得点

| ボタン | フィニッシュ | 点数 | エフェクトクラス | アニメーション |
|---|---|---|---|---|
| X | XTREME | 3 | `ef-xtreme` | `xtreme-in` → `xtreme-pulse`（無限ループ） |
| B | BURST | 2 | `ef-burst` | `burst-in` |
| O | OVER | 2 | `ef-over` | `over-in` |
| S | SPIN | 1 | `ef-spin` | `spin-in` |

`ef-xtreme` のみ入場アニメーション（`xtreme-in`）に加えて常時グロー点滅（`xtreme-pulse`）を併用する点が他3種と異なる。4種とも個別 keyframes で共通化しないこと（CLAUDE.md「4. score.html 保護」参照）。

### 決まり手分布の目安（評価用参考値）
SF≈57%、OF≈18%、XF≈18%、BF≈7%。分布に偏りがあるため、フラットな閾値ではなく全体平均比（1.3倍等）で評価すること。

### 勝利ポイントモード

| モード | 説明 |
|---|---|
| 4点モード | 4点先取（公式ルール） |
| 2点モード | 2点先取 |
| 2+モード | 2点先取で勝利判定、スコアは加算継続（3点・4点も表示可） |

### カウントダウン演出
`3 → 2 → 1 → GO! → SHOOT!` のシーケンスを `call-number-style` / `call-text-go-style` / `call-text-shoot-style` でアニメーション表示

- 数字（3/2/1）: `zoomInBounce`
- GO!: `slideCutIn`
- SHOOT!: `explodeShoot`

### システムボタン配置

全ボタン共通クラス `.system-btn` ＋個別クラス。`body.pro-mode` で**全て非表示**（`display: none !important`）になる。

| クラス | cmd/動作 | 配置 | 色 |
|---|---|---|---|
| `btn-reset` | `SYS_RESET` | 左上 | 水色（デフォルト） |
| `btn-reload` | `SYS_RELOAD`（`location.reload()`） | 左上（reset右） | ピンク `#ec4899` |
| `btn-fps` | `toggleFps()` | 左上 | 緑 `#22c55e` |
| `btn-cammode` | `toggleCamMode()` | 左上 | オレンジ `#ffaa00` |
| `btn-bg` | `toggleBackground()` | 左下 | 水色（デフォルト） |
| `btn-rotate` | `SYS_CAM` | 左下 | 水色 |
| `btn-pro` | `SYS_PRO` | 左下 | 水色 |
| `btn-hud` | `SYS_HUD` | 左下 | 緑 |
| `btn-timer-toggle` | `toggleTimerDuration()` | 右上 | 水色 |
| `btn-timer` | `TIMER` | 右上 | 水色（デフォルト） |
| `btn-stats` | `toggleStatsDisplay()` | 右下 | 水色 |
| `btn-undo` | `undoLastAction()` | 右下（stats と winpoint の間） | 緑 |
| `btn-winpoint` | `toggleWinPoint()` | 右下 | オレンジ |

### ベイブレード名表示
- P1/P2ごとに `beyblade-box-p1` / `beyblade-box-p2` 要素に表示
- `isStatsVisible` フラグが true のときのみ表示
- `SET_BEYBLADE` メッセージ受信で更新。`SET_MATCH` / `RESET` でクリア
- `winnerBey` が空文字の場合に不自然な日本語にならないよう `beyPhrase()` ヘルパーで空文字時は空文字を返す

### OBS設定
- iPhone 17 Pro Max 横向き最適化
- `body.pro-mode` でUIボタン非表示（配信中クリーンモード）
- `body.green-mode` でクロマキー背景

### CSV出力の後方互換性
新フィールド追加時は `|| ''` フォールバックを設け、旧保存データを破壊しないこと

---

## 4. イベントレポート仕様（tournament_de.html）

### 紙面カラーパレット（新聞配色）

| 用途 | カラー |
|---|---|
| 紙面背景 | `#f2f0ea` |
| 本文・見出し | `#14161a` |
| 副次テキスト | `#3f3f46` |
| 補足・注記 | `#57534e` |
| カード背景 | `#ffffff` |
| カード罫線 | `#d6d1c4` |
| セクション区切り | `#b9b4a8` |
| 見出しラベル・1位 | `#a8321e` |
| 2位以下の順位 | `#a8a29e` |
| マストヘッド帯 | `#14161a`（ロゴが白抜きのため） |

激闘カテゴリ色: フルスコア `#b91c1c` / 大逆転 `#b45309` / 番狂わせ `#15803d` /
完封 `#b45309` / XF連発 `#1d4ed8` / オンリーワン `#7c3aed`

決まり手バー: SF `#1d4ed8` / XF `#b45309` / OF `#c2410c` / BF `#be123c`（文字は全て白）

### 「本日の激闘」抽出ルール

優先順に判定し最大3件。同カテゴリからは1件まで。**GF・GFリセットは見出し記事で使うため除外**。

| 優先 | カテゴリ | 条件 |
|---|---|---|
| 0 | 因縁の一戦 | 📋名簿の家族関係カード（夫婦・親子・きょうだいのみ。サークル/属性は対象外） |
| 1 | フルスコア | 得点差1で決着 |
| 2 | 大逆転 | 2点以上リードされた側が勝利 |
| 3 | 番狂わせ | 初戦シード差8以上の下位が上位を撃破 |
| 4 | 完封 | 敗者0点 |
| 5 | XF連発 | 1試合中XF3回以上 |

- **スコアは必ず「勝者の得点 − 敗者の得点」の順**。対戦カード表記も勝者が先
- `note` は `REPORT_HIGHLIGHT_NOTES` の定型文を使う。
  **試合後コメント（`generateLocalComment()`）を流用しないこと**。
  元コメントは敗者を主語にすることがあり、勝者先頭の表記と矛盾する
- 「因縁の一戦」のみ `tryAdd()` の第3引数 `noteOverride` で関係性に応じた文を渡す
  （例: `WB FINAL、親を破る子の下剋上`）。他カテゴリは従来どおり定型文

### 「本日のオンリーワン」判定

- 集計対象は**ブレード・ラチェット・ビットのみ**（ロックチップ・アシスト・メタル・オーバーは対象外）
- 各パーツについて「他に何人が使ったか」を数え、その選手のパーツ集合の**平均値**が最小の選手を選出
  （合計ではなく平均。CXラインと BX/UX でパーツ数が異なるため）
- 同点時は独占パーツ数が多いほうを優先
- **参加10名未満、または独占パーツ0個の場合は `null`**（セクションごと非表示）

### 次回大会予定の取得

```
https://docs.google.com/spreadsheets/d/e/2PACX-1vR9shabC3eGCdRrP2oc-Rd-xrnsMR9n7fEnaDRl87GMImRiTYBWubjfSSt94wk1ZEhAqqLKcAHPpAha/pub?gid=0&single=true&output=csv
```

| # | 列 | # | 列 |
|---|---|---|---|
| 0 | 公開状況 | 9 | 大会形式 |
| 1 | イベント名 | 10 | コメント |
| 2 | 開催日 | 11 | 会場 |
| 3 | 受付開始時間 | 12 | 会場補足 |
| 4 | 大会開始時間 | 13 | GoogleマップURL |
| 5 | 大会終了時間 | 14 | トナメルURL |
| 6 | 参加資格 | 15 | ステータス |
| 7 | 参加費 | 16 | 種別 |
| 8 | 使用スタジアム | | |

- **`公開状況` が `公開` の行のみ対象。** 他は未公表の予定であり紙面に出してはならない
- レポート日付より後の最も早い開催日を選び、**同日複数件はイベント名を `／` で連結**する
- **`split(',')` でパースしてはならない。** `会場補足` にクォート内改行を含む値があり列がずれる
- トナメルURLは紙面に載せない
- **5秒タイムアウト。失敗しても必ずレポート生成を続行する**（会場のネットワークが不安定なため）

### PNG出力

- 2枚を順にダウンロード。**2枚目は300ms遅延**（連続ダウンロードのブラウザブロック対策）
- 「新しいタブで開く」は**ページごとに別ボタン**（1操作で2タブ開くとポップアップブロックに掛かる）
- iOS Safari は `a.download` が効かないことがあるため、両方の手段を残すこと
- 写真は選択直後に長辺1200px・JPEG品質0.85へ縮小する（元は4〜8MB）
- HEIC対策として `Image.onerror` と `FileReader.onerror` の両方を実装済み。20MB超は読み込む前に中断

---

## 5. SHOW_PREVIEW 送信データ仕様

`tournament_de.html` の `sendNextBattle()` → `score.html` の `showNextBattle()`。

| フィールド | 型 | 内容 |
|---|---|---|
| `p1` / `p2` | string | 選手名 |
| `label` | string | `"WINNERS - WB R2"` 形式 |
| `p1Stats` / `p2Stats` | object | `{ rank, power, rate }`。`rate` は `"60.00%"` 形式の文字列 |
| `h2hP1Wins` / `h2hP2Wins` | number | 直接対決の勝利数 |
| `catchphrase` | string | 煽り文（下記）。該当なしは空文字 |
| `showLogo` / `logoDataUrl` / `logoSrc` / `previewBackground` | — | `getShowPreviewHudFields()` が付与 |
| `p1members` / `p2members` | array | チーム戦時のメンバー名 |

### キャッチコピー（catchphrase）

**判定は送信側（tournament_de.html）で完結する。score.html は受信して表示するだけ。**
判定ロジックを score.html に持たせないこと（2ファイル同期の事故を防ぐため）。

| 優先 | 条件 | 例 |
|---|---|---|
| 0 | GF / GF RESET **かつ** 関係性あり | 親子で挑むグランドファイナル！ |
| 1 | 関係性あり（📋名簿 O〜T列） | 血を分けた親子対決！ |
| 2 | label に `GRAND FINAL`/`GF RESET`/`WB FINAL`/`LB FINAL`/`3RD PLACE` | 栄冠を懸けた決勝戦！ |
| 3 | H2H（両者1勝以上 → 一方のみ） | 宿命のライバル対決！ |
| 4 | 戦績（頂上 → ジャイキリ → 伯仲） | 魅せろ、ジャイアントキリング！ |
| 5 | 上記いずれも該当せず（最終手段） | 予測不能の初顔合わせ！ |

> ⚠️ **LOSER/敗者専用の汎用分岐（優先2の一部だった）は撤去済み。** LB戦のうち LB FINAL 以外
> （通常のLBラウンド）は WB と全く同じ優先3(H2H)→優先4(戦績)→優先5(初対戦)のチェーンを通る。
> 「サバイバル」「敗者復活」「背水」「崖っぷち」「生き残り」等の敗者専用語は、
> LB FINAL 以外のプールに追加しないこと（敗者戦の煽りが単調化していた原因のため）。

- 各カテゴリは**heads×tailsの組み合わせ**を `cpCombine()` でランダム合成（`cpFromRelation` は各8種以上、他は各12種以上）。
  直近8件のリングバッファと重複する場合は最大5回まで引き直す（`_catchphraseHistory`）
- ランク帯: `cpRankTier()` が `01-39F`/`40-59F`/`60-79F`/`80-89F`/`90-99F`/`XF` の 0〜5 を返す。
  `"--"` や未登録は `null` → **優先4をスキップして優先5へ**
- 頂上 = 両者80F以上 or 両者勝率60%以上 / ジャイキリ = 帯2段差以上 or BP差3000以上 / 伯仲 = それ以外
- **優先5（初顔合わせ）は必ずチェーンの最後に置くこと。** 優先3の中に置くと初対戦カードが
  すべてそこで確定し、優先4（戦績）に永久に到達しなくなる
- 表示: `score.html` の `#nb-catchphrase`（`.nb-catchphrase` / 黄 `#facc15` + ネオングロー）。
  空文字なら `display:none`。旧 `NEXT_BATTLE_CALL` は引数省略で空文字となり非表示
- 文言は**全角17文字以内**に収める（iPhone横向きで1行 `nowrap` に収まる上限）。
  `[...str].length <= 17` で判定（コードポイント単位。半角英数も1文字としてカウント）

---

## 6. BREAK_RECAP 送信データ仕様

`tournament_de.html` の `sendBreakStart()` / `sendBreakStartWithNext()` から `BREAK_START` の直後に送信。
`score.html` の `startBreakRecap(items, intervalMs)` が受信し、休憩オーバーレイ内でランダム順に自動切替表示する。

| フィールド | 型 | 内容 |
|---|---|---|
| `items` | array | 下記オブジェクトの配列。確定済み試合を新しい順（`updatedAt`降順）に最大50件 |
| `intervalMs` | number | 切替間隔（ミリ秒）。既定8000 |

`items[]` の各要素:

| フィールド | 型 | 内容 |
|---|---|---|
| `label` | string | `"LOSERS - LB R3"` 形式（`buildBreakRecapData()` 内で組み立て） |
| `p1` / `p2` | string | 選手名 |
| `score1` / `score2` | number \| null | 生スコア（p1-p2順）。`match.score` が未記録の場合は `null`（受信側は欄ごと非表示にする。"0-0"と誤読させないため） |
| `winnerIs` | number | `1` または `2` |
| `kimarite` | string \| null | 各バトルの決まり手を再生順にカンマ連結（例 `'XF,SF,OF,SF'`）。バトル記録が無ければ `null` |
| `comment` | string \| null | 試合後コメント（`match.comment` をそのまま使用。新規fetchはしない） |

- 休憩中に通信待ちを起こさないよう、Google Sheetsへの新規fetchは行わない
- 受信側は直近8件の履歴とは別に、**直前に表示した1件と連続しない**シャッフルバッグ方式で表示順を決める（`breakRecapBag`）。全件を一巡するまで再表示しない
- `BREAK_END` / `SHOW_SCORE_VIEW` / `HIDE_PREVIEW`（防御的）/ 新しい `BREAK_START` の受信で必ず `setInterval`・進行中のフェード`setTimeout`の両方を解放すること（`stopBreakRecap()`）

---

## 7. DE_PREVIEW_REQUEST / DE_PREVIEW_PAYLOAD フロー

`tournament_de_sub.html`（LB SUB子機）のブラケットカードから📢をタップした際の次戦予告フロー。
**キャッチフレーズ等の判定ロジックは `tournament_de.html`（親機）側で完結させ、子機側に複製しない**
（SHOW_PREVIEW/catchphraseの原則と同じ。2ファイル同期の事故を防ぐため）。

```
子機 tournament_de_sub.html          親機 tournament_de.html
  │  📢タップ                              │
  │  DE_PREVIEW_REQUEST ──────────────────▶│ handleDePreviewRequest()
  │  { bracket, roundIdx, matchIdx }       │  ・getDeRoundLabel() で label 生成
  │                                        │  ・loadH2HHistory() / loadRosterRelations()
  │                                        │    （キャッシュ済みなら即時。無ければ最大5秒）
  │                                        │  ・buildNextBattleCatchphrase() で catchphrase 生成
  │                                        │  ・親機自身の score.html 接続へ SHOW_PREVIEW を送信
  │  DE_PREVIEW_PAYLOAD ◀──────────────────┤  ・要求元の子機へ payload を返す
  │  { payload: {...SHOW_PREVIEW中身...} } │
  │                                        │
  │  payload をそのまま                    │
  │  { type:'SHOW_PREVIEW', ...payload }   │
  │  として自分のscore/score_sub接続へ転送 │
```

- トグル動作: 同じ試合の📢を再度タップしたら、子機はローカルの `subActiveNextBattleId` で判定し、
  親機への往復なしで自分のscore/score_sub接続へ直接 `HIDE_PREVIEW` を送る
- `DE_PREVIEW_REQUEST` は WB/LB/LB3位決定戦/GF/GF RESET のいずれの `bracket` 値でも送信されうる
  （子機のWINNERSタブはGRAND FINAL/GF RESETカードも表示するため）

---

## 8. score.html 複数接続について

`score.html` は `peer.on('connection')` で複数のPeerJS接続を同時に保持する（`activeConns` 配列、上限4本）。
新しい接続が来ても既存接続は切断しない。5本目が来たら最も古い接続を閉じる。
接続ステータス（`#link-dot` の `connected` クラス）は「1本以上openなら点灯」。
`broadcastToConns(msg)` は将来の全接続一斉送信用ヘルパー（現状未使用）。既存の `data.type` ハンドラは無変更。

---

## 9. LB再計算（recomputeLosersAndFinals）とベイ/決まり手データの保持

`tournament_de.html` の `recomputeLosersAndFinals()` は、WB側の結果変更等でLBの組み合わせが
変わりうるたびに（実際には `setWinner()` → `updateAdvancementsDE()` 経由でほぼ全ての結果確定時に）
LB全体を一旦ワイプして再ルーティングする。内部の `restoreLbSaved()` が、再ルーティング後の
各枠に「wipe前と同じ2選手が入っているか」を `rosterPairKey()`（参加者IDベース、名前やオブジェクト
参照ではない）で判定し、一致する枠にだけ `kimarite` / `comment` / `p1BeyUsed` / `p2BeyUsed` /
`beyP1` / `beyP2` / `battles` を復元する。

> ⚠️ **`restoreLbSaved()` の復元判定は `rosterPairKey` の一致のみで行うこと。**
> `s.winner !== null` を条件に加えると、進行中（`winner` がまだ `null`）の試合が
> 「保存済みの決着が無い」と誤判定されて else 分岐（クリア側）に落ち、
> 進行中の `battles` やベイ選択（`p1BeyUsed`/`beyP1`等）が丸ごと消える。
> サブ機での並行進行（P7）により、決着前のLB試合が存在する状態で
> 他の試合が確定してこの関数が呼ばれる経路は日常的に起こりうるため、
> 条件式に `s.winner` を混ぜないこと。
