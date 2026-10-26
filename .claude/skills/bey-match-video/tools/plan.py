#!/usr/bin/env python3
"""analyze の CSV から、編集の下書きになる候補時刻を出す。

usage: python3 -I plan.py metrics.csv

出力:
  OVERLAY  … NEXT BATTLE・トーナメント表・最終結果などの全画面画面の区間
  FINISH   … 決まり手表示（XTREME/OVER/BURST/SPIN FINISH）の出た時刻
  BEYNAME  … 下部のベイ名パネルが変わった時刻（＝ベイを見せ合ったタイミングの目安）

あくまで候補。WINNER の枠や画面遷移でも反応するので、必ず frames + sheet で目視確認してから
segments を組むこと（SKILL.md の手順 3〜4）。
"""
import csv, sys

rows = [{k: float(v) for k, v in r.items()} for r in csv.DictReader(open(sys.argv[1]))]
fmt = lambda t: f"{int(t // 60)}:{t % 60:05.2f}"


def peaks(key, th, gap=3.0):
    ev, last = [], -99.0
    for r in rows:
        if r[key] > th and r['t'] - last > gap:
            ev.append(r['t'])
        if r[key] > th:
            last = r['t']
    return ev


overlay, cur = [], None
for r in rows:
    d = r['lp'] > 0.85 and r['rp'] > 0.85
    if d and cur is None:
        cur = r['t']
    if not d and cur is not None:
        if r['t'] - cur > 1.0:
            overlay.append((cur, r['t']))
        cur = None
if cur is not None:
    overlay.append((cur, rows[-1]['t']))

fin = peaks('sat', 60)
bey = sorted(set(round(t, 1) for t in peaks('pld', 18, 2) + peaks('prd', 18, 2)))

print('OVERLAY', ' '.join(f'{fmt(a)}-{fmt(b)}' for a, b in overlay))
print('FINISH ', ' '.join(fmt(t) for t in fin))
print('BEYNAME', ' '.join(fmt(t) for t in bey))
print()
print('# 秒表記（segments 用）')
print('overlay =', [(round(a, 2), round(b, 2)) for a, b in overlay])
print('finish  =', [round(t, 2) for t in fin])
print('beyname =', bey)
