"""DE bracket verification - same logic as tournament_de.html (20 players).
_verify_de_bracket.ps1 の Python 移植。実行: python3 _verify_de_bracket.py"""
from _de_topology import build_bracket, match_label, fmt_to

slots, wb, lb = build_bracket()

print('=== WINNERS R0 MATCHUPS ===')
for m, match in enumerate(wb[0]):
    lbl = match_label('wb', 0, m)
    print(f"{lbl:<8} {match['p1']} vs {match['p2']}  loser->{fmt_to(match['loserTo'])}")

print()
print('=== WB FULL ROUTING ===')
for r in range(len(wb)):
    for m, match in enumerate(wb[r]):
        lbl = match_label('wb', r, m)
        print(f"{lbl:<10} win->{fmt_to(match['winnerTo']):<16} lose->{fmt_to(match['loserTo'])}")

print()
print('=== LB INCOMING SOURCES ===')
for r in range(len(lb)):
    for m, match in enumerate(lb[r]):
        lbl = match_label('lb', r, m)
        from_wb = [match_label('wb', wr, wm)
                   for wr in range(len(wb)) for wm in range(len(wb[wr]))
                   if (lt := wb[wr][wm]['loserTo']) and lt['bracket'] == 'lb'
                   and lt['round'] == r and lt['index'] == m]
        from_lb = [match_label('lb', lr, lm)
                   for lr in range(len(lb)) for lm in range(len(lb[lr]))
                   if (wt := lb[lr][lm]['winnerTo']) and wt['bracket'] == 'lb'
                   and wt['round'] == r and wt['index'] == m]
        s1 = 'WB:' + ','.join(from_wb) if from_wb else ''
        s2 = 'LB:' + ','.join(from_lb) if from_lb else ''
        print(f"{lbl:<8} slot1<-{s1:<30} slot2<-{s2:<30} win->{fmt_to(match['winnerTo'])}")

print()
print('=== SEED SLOTS ===')
for i, s in enumerate(slots):
    print(f'slot[{i:2d}] = {s}')
