# DE版機能の他アプリ展開プロンプト（Sonnet用）

調査日: 2026-10-17 ／ 基準: `tournament_de.html`（8838行・関数398個）

## 機能差分マトリクス

| # | 機能（DE側の参照箇所） | tournament | evo | souatari | tag | freebattle |
|---|---|:-:|:-:|:-:|:-:|:-:|
| A | 結果入力UNDO（`pushDeUndoSnapshot` L4128 / `undoDeLastAction` L4139） | ❌ | ❌ | ❌ | ❌ | ❌ |
| B | ベイ写真の圧縮保存（`reportResizePhotoFile` L7157 / `setBayPhotoDataUrlByName` L2674 / 撮影前 `saveState` L2685） | ❌ 非圧縮 | ❌ 非圧縮 | — | — | — |
| C | 写真一括削除・容量表示（`execClearAllBayPhotos` L2632） | ✅ | ❌ | — | — | — |
| D | 名簿の関係性（`loadRosterRelations` L1298 / `getRelation` L1331 / `buildRelationPrefix` L1347） | ❌ | ❌ | ❌ | ❌ | ❌ |
| E | 次戦予告キャッチコピー（`buildNextBattleCatchphrase` L4493 ＋ `cp*` 群 → `SHOW_PREVIEW.catchphrase`） | ❌ | ❌ | ❌ | ❌ | ❌ |
| F | 休憩中の振り返り（`buildBreakRecapData` L4537 / `sendBreakRecap` L4570 → `BREAK_RECAP`） | ❌ | ❌ | ❌ | ❌ | ❌ |
| G | 休憩オーバーレイ（`BREAK_START`/`BREAK_END`） | ✅ | ✅ | ✅ | ❌ | ❌ |
| H | 試合後コメント（`generateLocalComment` L2300 / `terminateLoserPraise` L2170 / 関係性枕詞） | △ 旧版 | ❌ | △ 旧版 | ❌ | △ 旧版 |
| I | 決まり手の大会中ライブ集計（`getLiveFinCounts` L2277） | ❌ | ❌ | ❌ | ❌ | ❌ |
| J | QR告知（`sendQrAnnounceMsg` L1172 → `SHOW_QR_ANNOUNCE`） | ✅ | ❌ | ✅ | ❌ | ❌ |
| K | イベントレポート（`openReportModal` L6937 ほか `report*` 群） | ❌ | ❌ | ✅ 移植済 | ❌ | ❌ |
| L | UI原則（`:focus-visible` L48〜 / `cyber-on-*` トークン） | ❌ | ❌ | ❌ | ❌ | ❌ |

DE専用で展開対象外: LB/GFトポロジー、サブ機連携（`DE_*` / `handleSubMessage`）、Tonamel24シード、進行ガイド（`computeSuggestedWbMatch`）

---

## 使い方

- **1プロンプト＝1セッション**。各アプリのプロンプトは Phase ごとに区切ってあるので、Phase 1 完了→ローカル確認→次の Phase の順で進める
- 推奨順: ① tournament.html（UIマスター）→ ② tournament_evo.html → ③ souatari.html → ④ tag.html → ⑤ freebattle.html
- tournament.html で実装した版を、②以降は「tournament.html の実装を移植元にしてよい」として使う（DEより差分が小さい）

---

## ① tournament.html

```
tournament_de.html にある以下の機能を tournament.html に移植してください。
CLAUDE.md のルール（single-file・PeerJS type保護・localStorageキー分離・iOS対応・UI原則）に従うこと。
DE側は巨大なので Grep＋部分Readで該当関数だけ読むこと。DE固有のブラケット構造（winnersBracket/losersBracket/grandFinal）は tournament.html のブロック戦＋準決勝・決勝・3位決定戦の構造に置き換えて実装すること。
着手前に対象関数と変更方針を一言宣言してから実装。Phase ごとに止めて確認手順を報告してください。

■ Phase 1（データ保全・最優先）
1. ベイ確認写真の圧縮保存
   - DE の reportResizePhotoFile(file, 1280)（L7157）相当を追加し、長辺1280px・JPEG 0.85 で保存
   - setBayPhotoDataUrlByName を try/catch 付き・boolean 返却に変更（DE L2674）。false ならプレビュー更新しない。QuotaExceededError は showAlert で通知し握りつぶさない
   - startBayPhotoCapture で input.click() の直前に saveState()（DE L2685）
   - キーは bayPhoto_{encodeURIComponent(名前)} を維持し、旧形式キーも読み取り・削除対象に
2. 結果入力 UNDO
   - DE の pushDeUndoSnapshot / undoDeLastAction / updateDeUndoButtonState（L4128〜）を参考に、tournament.html の勝者確定・取り消し前にスナップショットを積む
   - 対象はブラケット状態一式（ブロック戦・準決勝・決勝・3位決定戦）。上限15件、localStorage には保存しない、UNDO時に syncToSheets は呼ばない
   - UNDOボタンは DE の btn-de-undo と同じ位置・見た目で配置（44px以上、無効時は opacity＋disabled）

■ Phase 2（配信演出）
3. 名簿の関係性データ
   - loadRosterRelations / getRelation / rosterPairKey / buildRelationPrefix を移植（DE L1298〜）。取得失敗・5秒タイムアウトは null で通常動作
4. 次戦予告キャッチコピー
   - buildNextBattleCatchphrase と cp* 関数群（DE L4493 付近）を移植し、SHOW_PREVIEW に catchphrase フィールドを追加（type は変えない）
   - DE固有の段階名（WB FINAL / LB FINAL / GF）は tournament.html の段階名（ブロック決勝・準決勝・決勝・3位決定戦）に置き換え
   - 移植後 python3 _verify_cp.py が通ることを確認（必要なら tournament.html 用のケースを追加）
5. 休憩中の振り返り
   - buildBreakRecapData / sendBreakRecap（DE L4537〜）を移植し、BREAK_START 送信直後に BREAK_RECAP を送る。フィールドは REFERENCE.md 6章に準拠
6. 試合後コメントの更新
   - generateLocalComment（DE L2300）を DE 版に追従：terminateLoserPraise、関係性枕詞 buildRelationPrefix、節目試合のまとめ文（buildRoundSummary を tournament.html の段階名で）
7. 決まり手ライブ集計
   - getLiveFinCounts（DE L2277）を移植し、次戦予告の戦績表示で大会中の決まり手を反映

■ Phase 3（レポート）
8. イベントレポート
   - DE の openReportModal 以降の report* 群を移植。souatari.html に移植済みの実装があるので、そちらとの差分が小さければ souatari 版を土台にしてよい
   - 紙面2枚の構成・html2canvas の制約（box-shadow等禁止、fonts.ready、transform解除、flex:0 0 auto、maintitle_white_trim.png）は CLAUDE.md「イベントレポート機能」に従う
   - localStorage キーは tbh_tournament_report_photo / tbh_tournament_report_note のように大会本体（tbh_tournament）と分離。saveState/loadState は変更しない

各 Phase の最後に、変更した関数と行番号、localhost:5500 での確認手順、UI原則6項目の確認結果1行を報告してください。
```

---

## ② tournament_evo.html

```
tournament_evo.html に、tournament.html（DE版から移植済み）と同等の機能を追加してください。
移植元は tournament.html を優先し、tournament.html に無いものだけ tournament_de.html を参照すること。
CLAUDE.md のルールに従い、EVO固有の「当日参加抽選タブ」の挙動は変更しないこと。着手前に方針を一言宣言。

■ Phase 1
1. ベイ写真の圧縮保存（1280px・JPEG 0.85・boolean返却・撮影前 saveState・try/catch）
2. 写真一括削除＋容量表示（execClearAllBayPhotos / listBayPhotoKeys / getBayPhotoUsage）— evo には未実装
3. 結果入力 UNDO（上限15件・メモリのみ・UNDO時は syncToSheets を呼ばない）

■ Phase 2
4. 名簿の関係性・次戦予告キャッチコピー（SHOW_PREVIEW.catchphrase）・BREAK_RECAP
5. 試合後コメント（generateLocalComment / sendMatchComment / toggleCommentMode）— evo には未実装なので tournament.html から丸ごと移植
6. 決まり手ライブ集計（getLiveFinCounts）
7. QR告知（sendQrAnnounceMsg → SHOW_QR_ANNOUNCE / HIDE_QR_ANNOUNCE、受付終了・大会開始で自動OFF）

■ Phase 3
8. イベントレポート（tournament.html 版を移植。localStorage キーは tbh_evo_report_* 等で本体と分離）

Phase ごとに変更箇所・確認手順（localhost:5500）・UI原則確認1行を報告してください。
```

---

## ③ souatari.html

```
souatari.html（総当たりリーグ）に tournament_de.html の以下の機能を移植してください。
イベントレポートは移植済みなので対象外（DE側で入った改善との差分があれば一覧だけ報告し、実装はしない）。
総当たりなのでブラケットではなく「対戦表＋勝点順位表」構造に合わせて実装すること。CLAUDE.md のルールに従い、着手前に方針を一言宣言。

■ Phase 1
1. 結果入力 UNDO（DE の pushDeUndoSnapshot / undoDeLastAction を参考。対象は全試合結果と順位計算の元データ。上限15件・メモリのみ・UNDO時は syncToSheets を呼ばない）

■ Phase 2
2. 名簿の関係性（loadRosterRelations / getRelation / buildRelationPrefix）
3. 次戦予告キャッチコピー（SHOW_PREVIEW.catchphrase）。L920 と L2593 の2箇所の送信を両方対応。段階は「第N試合」「首位攻防」「最終戦」等、総当たり向けに cpFromStage を調整
4. 試合後コメントを DE 版に追従（terminateLoserPraise・関係性枕詞）
5. BREAK_RECAP（BREAK_START 直後に送信）
6. 決まり手ライブ集計（getLiveFinCounts を総当たりの試合配列で）

Phase ごとに変更箇所・確認手順（localhost:5500）・UI原則確認1行を報告してください。
```

---

## ④ tag.html

```
tag.html（タッグリーグ：スイス＋決勝T）に tournament_de.html / tournament.html の以下の機能を移植してください。
タッグ（2人1組）なので、関係性・キャッチコピー・コメントは「チーム vs チーム」で成立するよう調整すること（チーム内の関係性＝「親子タッグ」等も扱えると良い）。
アクセントはピンク（cyber-pink）のまま。CLAUDE.md のルールに従い、着手前に方針を一言宣言。

■ Phase 1
1. 結果入力 UNDO（スイスラウンド・決勝Tの両方。上限15件・メモリのみ・UNDO時は syncToSheets を呼ばない）

■ Phase 2
2. 休憩オーバーレイ BREAK_START / BREAK_END（tournament.html の sendBreakStart 系を移植。必須フィールド p1/p2/logoDataUrl/previewBackground/logoSrc/showLogo）＋ 直後の BREAK_RECAP
3. 名簿の関係性＋次戦予告キャッチコピー（L2199 の SHOW_PREVIEW に catchphrase を追加）
4. 試合後コメント（generateLocalComment / sendMatchComment / toggleCommentMode を移植。タッグ向けに文面調整）
5. QR告知（SHOW_QR_ANNOUNCE / HIDE_QR_ANNOUNCE）

■ Phase 3（任意・着手前に確認を取る）
6. イベントレポート（スイス順位＋決勝T結果で紙面構成を再設計する必要があるため、構成案を先に提示して承認を得てから実装）

Phase ごとに変更箇所・確認手順（localhost:5500）・UI原則確認1行を報告してください。
```

---

## ⑤ freebattle.html

```
freebattle.html（フリー対戦）に tournament.html / tournament_de.html の以下の機能を移植してください。
大会ではないので順位・段階の概念はない。キャッチコピーは対戦成績・関係性中心、段階名は使わないこと。
アクセントはオレンジ（#fb923c）のまま。CLAUDE.md のルールに従い、着手前に方針を一言宣言。

■ Phase 1
1. 結果入力 UNDO（直近の対戦結果記録を取り消せる。上限15件・メモリのみ）

■ Phase 2
2. 休憩オーバーレイ BREAK_START / BREAK_END ＋ BREAK_RECAP（その日の対戦記録から振り返りを生成）
3. 名簿の関係性＋次戦予告キャッチコピー（L1987 の SHOW_PREVIEW に catchphrase を追加）
4. 試合後コメントを DE 版に追従（terminateLoserPraise・関係性枕詞）
5. QR告知（SHOW_QR_ANNOUNCE / HIDE_QR_ANNOUNCE）

Phase ごとに変更箇所・確認手順（localhost:5500）・UI原則確認1行を報告してください。
```

---

## 全アプリ共通（最後にまとめて）

```
操作系アプリ（tournament.html / tournament_evo.html / souatari.html / tag.html / freebattle.html）に、
tournament_de.html の L48〜 にある :focus-visible リングと cyber-on-* トークン（tailwind.config）を追加してください。
既存の塗り色は変更せず、塗りボタン上の白文字だけを on-color に差し替えること。cyber-red の塗りボタンはアウトライン形式へ。
1ファイルずつ実施し、変更したボタンの一覧を報告してください。（UI変更なので着手前に方針を宣言）
```
