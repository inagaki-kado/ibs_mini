# 詳細リファレンス

CLAUDE.md から切り出した詳細仕様。実装時に必要になったら参照すること。

---

## PeerJS REMOTE_CMD コマンド一覧

| cmd値 | 動作 |
|---|---|
| `P1_X` / `P2_X` | P1/P2 にXTREMEフィニッシュ(+3点) |
| `P1_B` / `P2_B` | P1/P2 にBURSTフィニッシュ(+2点) |
| `P1_O` / `P2_O` | P1/P2 にOVERフィニッシュ(+2点) |
| `P1_S` / `P2_S` | P1/P2 にSPINフィニッシュ(+1点) |
| `RESET` | スコアリセット |
| `SYS_PRO` | PROモード切替（UIボタン非表示） |
| `SYS_STATS` | 戦績表示切替 |
| `SYS_CAM` | カメラ180°反転 |
| `REPLAY_TOGGLE` | リプレイモード切替（Enter） |
| `REPLAY_LATEST` | ハイライト再生（末尾15秒から） |
| `REPLAY_REV` | −5秒シークして再生 |
| `REPLAY_PLAY` | 再生 / 一時停止 |
| `REPLAY_FRAME_FWD` / `REPLAY_FRAME_REV` | ±1フレーム（60fps推定、30fpsフォールバック） |
| `REPLAY_SLOW` | スロー再生（0.5→0.25→0.1x サイクル） |
| `REPLAY_LOOP` | ループON/OFF（現在位置から遡ってループ） |
| `REPLAY_LOOP_LEN` | ループ秒数サイクル（3→4→5秒） |
| `REPLAY_ZOOM` | 2xズーム切替（タップ位置中心） |
| `REPLAY_SEEK_FWD` / `REPLAY_SEEK_REV` | ±1秒シーク |

リプレイ中も `P1_X` 等のスコアコマンドは受付可（リプレイは終了せず一時停止して加点）。

### score.html 接続コード URL パラメータ

`score.html?peer=1234` で PeerJS 接続コード（4桁数字）を上書き。未指定時は `0511`。
Peer ID は `itabashi-link-{code}` 形式。

---

## score.html HUD仕様（Ver.34）

### ランク表示（ITABASHIX-TOWER方式）

| 階層 | クラス | カラー |
|---|---|---|
| 01F〜39F | `rank-white` | `#FFFFFF` |
| 40F〜59F | `rank-blue` | `#0EA5E9` |
| 60F〜79F | `rank-green` | `#00FF41` |
| 80F〜89F | `rank-purple` | `#A855F7` |
| 90F〜99F | `rank-red` | `#EF4444` |
| XF | `rank-gold` | `#F59E0B`（gold-pulseアニメーション付き） |

### 勝利ポイントモード（toggleWinPoint()サイクル）
`4 → 2 → 2+ → 3 → 4` の順でサイクル

### フィニッシュタイプ・得点

| ボタン | フィニッシュ | 点数 | エフェクトクラス |
|---|---|---|---|
| X | XTREME | 3 | `ef-xtreme`（赤・xtreme-in + pulse） |
| B | BURST | 2 | `ef-burst`（金・burst-in） |
| O | OVER | 2 | `ef-over`（オレンジ・slide cut-in） |
| S | SPIN | 1 | `ef-spin`（青・spin-in） |

### リプレイ操作（Ver.34+）

| 操作 | キー（リプレイ中） | REMOTE_CMD |
|---|---|---|
| 再生/停止 | `5` | `REPLAY_PLAY` |
| −5秒 | `8` | `REPLAY_REV` |
| スロー | `2` | `REPLAY_SLOW` |
| ±1フレーム | `+` / `-` | `REPLAY_FRAME_FWD` / `REPLAY_FRAME_REV` |
| ループON/OFF | `L` | `REPLAY_LOOP` |
| ループ秒数 | `K` | `REPLAY_LOOP_LEN` |
| 2xズーム | `Z` | `REPLAY_ZOOM` |
| ±1秒シーク | `←` / `→` | `REPLAY_SEEK_REV` / `REPLAY_SEEK_FWD` |
| ハイライト | `Tab` | `REPLAY_LATEST` |
| リプレイ終了 | `Enter` | `REPLAY_TOGGLE` |
| P1/P2加点 | `7/4/1/0`, `9/6/3/.` | `P1_X` 等（リプレイ継続） |

- `body.replay-mode`: スコアHUDのみ半透明（`pro-mode` 時は非表示）
- シークバー `#replay-controls`、ループ範囲 `#replay-loop-range`（ピンク帯）
- ダブルタップ（400ms以内）でタップ位置中心2xズーム
- ステータスバッジ `refreshReplayStatus()`（再生速度・LOOP秒数・ZOOM）

---

## ベイブレードパーツ登録仕様

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

### パーツ登録フロー

```
BX/UXライン:    ブレード(BX/UX) → ラチェット(RA) → ビット(BT)
CXライン:       ロックチップ(RC) → メインブレード(CX) → アシスト(AB) → ラチェット(RA) → ビット(BT)
CX(EX)ライン:   ロックチップ(RC) → メタル(MB) → オーバー(OB) → アシスト(AB) → ラチェット(RA) → ビット(BT)
```

パーツ結合時は**記号を使わず**名前を詰めて1つの文字列にする。
例: `ドランバスターRatchet3-60F`

---

## tournament_de.html 主要関数

| 関数 | 役割 |
|---|---|
| `buildStandardDEBracket(slots)` | WB/LB/GF 骨格生成・`_meta` ルーティング付与 |
| `wireDERouting()` | 勝者/敗者の落下先（標準DEマップ） |
| `updateAdvancementsDE()` | 勝敗伝播・BYE自動処理・GFリセット判定 |
| `getMatchByCoords(bracket, r, m)` | `'wb'` / `'lb'` / `'gf'` / `'gf_reset'` / `'lb3rd'` |
| `getBracketSnapshot()` | Sheets用。`format: 'double_elimination'` で SE 版と判別 |
| `switchDeSubTab('wb'|'lb')` | WINNERS / LOSERS タブ切替 |

### getBracketSnapshot() スキーマ

```javascript
{
  format: 'double_elimination',
  version: 1,
  globalBlockSize, blockMap,
  playerCount, bracketSize,
  winnersBracket, losersBracket,
  grandFinal, grandFinalReset, lbThirdPlace,
  playedPairs, gfResetRequired
}
```
