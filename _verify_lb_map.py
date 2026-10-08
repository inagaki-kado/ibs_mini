"""Map image WB numbers to DE app; compare LB topology.
_verify_lb_map.ps1 の Python 移植。実行: python3 _verify_lb_map.py"""
from _de_topology import build_bracket, match_label, fmt_to

# DE app WB label -> bracket image match number
DE_TO_IMG = {
    'R0-A': 1, 'R0-B': 2, 'R0-C': 3, 'R0-D': 4,
    'W2-8': 5, 'W2-6': 6, 'W2-4': 7, 'W2-2': 8,
    'W2-3': 9, 'W2-5': 10, 'W2-7': 11, 'W2-1': 12,
    'W3-1': 15, 'W3-2': 16, 'W3-3': 13, 'W3-4': 14,
    'W4-1': 18, 'W4-2': 17, 'WB-FINAL': 19,
}

slots, wb, lb = build_bracket()

print('=== WB: DE label -> Image # ===')
for r in range(len(wb)):
    for m, match in enumerate(wb[r]):
        lbl = match_label('wb', r, m)
        img = DE_TO_IMG.get(lbl, '?')
        print(f"{lbl:<10} -> img({img})  lose->{fmt_to(match['loserTo'])}")

print()
print('=== LB: each slot sources (as image WB #) ===')
for r in range(len(lb)):
    for m, match in enumerate(lb[r]):
        s1, s2 = [], []
        for wr in range(len(wb)):
            for wm in range(len(wb[wr])):
                lt = wb[wr][wm]['loserTo']
                if lt and lt['bracket'] == 'lb' and lt['round'] == r and lt['index'] == m:
                    lbl = match_label('wb', wr, wm)
                    num = DE_TO_IMG.get(lbl, lbl)
                    (s1 if lt['slot'] == 1 else s2).append(str(num))
        for lr in range(len(lb)):
            for lm in range(len(lb[lr])):
                wt = lb[lr][lm]['winnerTo']
                if (wt and wt['bracket'] == 'lb' and wt['round'] == r
                        and wt['index'] == m and wt['slot'] == 1):
                    s1.append(f'LB:L{lr + 1}-{lm + 1}')
        print(f"L{r + 1}-{m + 1}: slot1<-[{','.join(s1)}]  slot2<-[{','.join(s2)}]  win->{fmt_to(match['winnerTo'])}")

print()
print('=== IMAGE LB expected paths (from image) ===')
print('G1: (1)+(5)->(9)->(13)->vs(17)')
print('G2: (2)+(6)->(10)->(14)->merge G1')
print('G3: (3)+(7)->(11)->(15)->vs(18)')
print('G4: (4)+(8)->(12)->(16)->merge G3')
print('Semi: G1winner vs G2winner; G3winner vs G4winner')
print('Final: vs(19)->LOSERS CHAMP')
