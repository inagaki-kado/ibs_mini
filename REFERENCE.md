# 板橋ベイブレード会 — REFERENCE.md

> CLAUDE.md から参照される詳細リファレンス。
> ファイル一覧・技術スタック・各アプリ固有仕様・BP計算・外部サービス連携は **CLAUDE.md が正**。
> ここには CLAUDE.md に書ききれない詳細（コマンド一覧・パーツ仕様・HUD仕様）のみを置く。

---

## 1. PeerJS REMOTE_CMD コマンド一覧

`REMOTE_CMD` メッセージの `cmd` フィールドに指定する値の一覧。

| cmd値 | 動作 |
|---|---|
| `P1_X` / `P2_X` | P1/P2 に XTREME フィニッシュ（+3点） |
| `P1_B` / `P2_B` | P1/P2 に BURST フィニッシュ（+2点） |
| `P1_O` / `P2_O` | P1/P2 に OVER フィニッシュ（+2点） |
| `P1_S` / `P2_S` | P1/P2 に SPIN フィニッシュ（+1点） |
| `RESET` | スコアリセット |
| `SYS_PRO` | PRO MODE 切替（UIボタン非表示・配信用クリーンモード） |
| `SYS_STATS` | 戦績表示切替 |
| `SYS_CAM` | カメラ180°反転 |
| `SYS_SWAP` | P1/P2 入替（score.html は内部変数を物理入替。加点コマンドのside反転は不要） |

> ⚠️ **未確定**: 上記は現時点で確認済みの主要コマンド。score.html 実装に新しい `cmd` 値を追加した場合は、このテーブルに追記すること。

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

| ボタン | フィニッシュ | 点数 | エフェクトクラス |
|---|---|---|---|
| X | XTREME | 3 | `ef-xtreme`（赤・xtreme-in + pulse） |
| B | BURST | 2 | `ef-burst`（金・burst-in） |
| O | OVER | 2 | `ef-over`（オレンジ・slide cut-in） |
| S | SPIN | 1 | `ef-spin`（青・spin-in） |

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
