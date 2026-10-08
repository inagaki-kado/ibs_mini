"""tournament_de.html の DE トポロジー検証用 共通ロジック（_verify_*.ps1 の Python 移植）。"""
BYE = 'BYE'
COLORS = ['A', 'B', 'C', 'D']


def wb_drop_index(wb_round, m, count):
    if count <= 1:
        return 0
    if wb_round % 2 == 1:
        return count - 1 - m
    return (m + count // 2) % count


def lb_round_match_count(P, lr):
    return P >> (lr // 2 + 2)


def new_match(bracket, rnd, index):
    return {'p1': None, 'p2': None, 'bracket': bracket, 'round': rnd,
            'index': index, 'winnerTo': None, 'loserTo': None}


def build_block_grouped_slots(P=32, slots_per_block=8, bye_match_count=4, players_per_block=5):
    slots = [BYE] * P
    for bi in range(4):
        c = COLORS[bi]
        base = bi * slots_per_block
        ps = [f'{c}-{n}' for n in range(1, players_per_block + 1)]
        real = max(0, len(ps) - bye_match_count)
        for i, p in enumerate(ps):
            if i < real * 2:
                idx = base + i
            else:
                idx = base + real * 2 + (i - real * 2) * 2
            slots[idx] = p
    return slots


def wire_de_routing(wb, lb):
    lb_rounds = len(lb)
    for r in range(len(wb)):
        for m in range(len(wb[r])):
            x = wb[r][m]
            if r < len(wb) - 1:
                x['winnerTo'] = dict(bracket='wb', round=r + 1, index=m // 2, slot=m % 2 + 1)
            else:
                x['winnerTo'] = dict(bracket='gf', round=0, index=0, slot=1)
            if r == 0:
                x['loserTo'] = dict(bracket='lb', round=0, index=m // 2, slot=m % 2 + 1)
            elif r < len(wb) - 1:
                x['loserTo'] = dict(bracket='lb', round=r * 2 - 1,
                                    index=wb_drop_index(r, m, len(wb[r])), slot=2)
            else:
                x['loserTo'] = dict(bracket='lb', round=lb_rounds - 1, index=0, slot=2)
    for r in range(len(lb)):
        for m in range(len(lb[r])):
            x = lb[r][m]
            if r == lb_rounds - 1:
                x['winnerTo'] = dict(bracket='gf', round=0, index=0, slot=2)
            elif r % 2 == 0:
                x['winnerTo'] = dict(bracket='lb', round=r + 1, index=m, slot=1)
            elif r == lb_rounds - 2:
                x['winnerTo'] = dict(bracket='lb', round=r + 1, index=0, slot=1)
            else:
                x['winnerTo'] = dict(bracket='lb', round=r + 1, index=m // 2, slot=m % 2 + 1)


def match_label(bracket, rnd, index):
    r0_zero = {0: 'A', 4: 'B', 8: 'C', 12: 'D'}
    r0_norm = [1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15]
    if bracket == 'lb':
        return f'L{rnd + 1}-{index + 1}'
    if rnd == 0:
        if index in r0_zero:
            return f'R0-{r0_zero[index]}'
        if index in r0_norm:
            return f'R1-{r0_norm.index(index) + 1}'
    if rnd == 4:
        return 'WB-FINAL'
    return f'W{rnd + 1}-{index + 1}'


def fmt_to(to):
    if not to:
        return ''
    if to['bracket'] == 'gf':
        return f"GF({to['slot']})"
    return f"L{to['round'] + 1}-{to['index'] + 1}({to['slot']})"


def build_bracket(P=32, k=5, lb_rounds=8):
    """20人(4ブロック×5人)前提の WB/LB を組み立てて返す: (slots, wb, lb)"""
    slots = build_block_grouped_slots(P)
    wb = [[new_match('wb', r, i) for i in range(P >> (r + 1))] for r in range(k)]
    lb = [[new_match('lb', r, i) for i in range(lb_round_match_count(P, r))] for r in range(lb_rounds)]
    wire_de_routing(wb, lb)
    for m in range(P // 2):
        wb[0][m]['p1'] = slots[m * 2]
        wb[0][m]['p2'] = slots[m * 2 + 1]
    return slots, wb, lb
