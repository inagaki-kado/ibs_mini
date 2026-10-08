"""次戦予告キャッチコピー生成ロジック（tournament_de.html の buildNextBattleCatchphrase 系）の検証用。
_verify_cp.js の Python 移植。実行: python3 _verify_cp.py（文字数上限などのセルフチェックを行う）"""
import random
import re

_NUM_RE = re.compile(r'^[+-]?(\d+\.?\d*|\.\d+)')
_INT_RE = re.compile(r'^[+-]?\d+')


def pick_random(arr):
    return random.choice(arr)


def cp_rank_tier(rank_str):
    s = str(rank_str or '').strip().upper()
    if not s or s == '--':
        return None
    if s.startswith('X'):
        return 5
    m = _INT_RE.match(s)  # JS parseInt 相当（先頭の整数のみ）
    if not m:
        return None
    n = int(m.group())
    if n < 40:
        return 0
    if n < 60:
        return 1
    if n < 80:
        return 2
    if n < 90:
        return 3
    return 4


def cp_rate_num(rate_str):
    m = _NUM_RE.match(str(rate_str or '').replace('%', '').strip())
    return float(m.group()) if m else None


# 前半×後半を組み合わせる。直近8件のリングバッファと重複する場合は最大5回まで引き直す
_catchphrase_history = []
CATCHPHRASE_HISTORY_LIMIT = 8


def cp_combine(heads, tails):
    out = pick_random(heads) + pick_random(tails)
    tries = 0
    while out in _catchphrase_history and tries < 5:
        out = pick_random(heads) + pick_random(tails)
        tries += 1
    _catchphrase_history.append(out)
    if len(_catchphrase_history) > CATCHPHRASE_HISTORY_LIMIT:
        _catchphrase_history.pop(0)
    return out


def cp_rel_word(rel):
    if not rel:
        return ''
    k = rel.get('kind')
    if k == 'spouse':
        return '夫婦'
    if k == 'parent_child':
        return '母子' if rel.get('motherSide') else '親子'
    if k == 'sibling':
        return 'きょうだい'
    if k == 'same_circle':
        return '同門'
    if k == 'same_attr':
        return rel.get('attr')
    if k == 'cross_circle':
        return '他流'
    return ''


# 優先1: 関係性ベース
def cp_from_relation(rel):
    if not rel:
        return ''
    k = rel.get('kind')
    if k == 'spouse':
        return cp_combine(
            ['愛と闘志の', '誓いを交わした', '家庭を懸けた', '最も近い好敵手、', '譲れぬ', '公私を懸けた', '阿吽の呼吸で挑む', '日常を持ち込んだ'],
            ['夫婦対決！', '夫婦決戦！', '夫婦バトル！', '夫婦の一戦！', 'カップルマッチ！', '夫婦の意地！', '夫婦ダービー！', '夫婦頂上決戦！'])
    if k == 'parent_child':
        kin = '母子' if rel.get('motherSide') else '親子'
        return cp_combine(
            ['血を分けた', '世代を超えた', '絆を懸けた', '受け継がれし', '譲れぬ想いの', '親から子へ', '背中を追いかけた', '血筋が交わる'],
            [f'{kin}対決！', f'{kin}決戦！', f'{kin}バトル！', f'{kin}の一戦！', 'ファミリーマッチ！', f'{kin}頂上戦！', f'{kin}の意地！', f'{kin}激突！'])
    if k == 'sibling':
        return cp_combine(
            ['負けられない', '幼き日からの', '同じ屋根の下、', '譲れぬ意地の', '血で血を洗う', '切磋琢磨してきた', '幼馴染以上の', '同じ血を継ぐ'],
            ['きょうだい対決！', 'きょうだい決戦！', 'きょうだいバトル！', 'きょうだいの一戦！', 'ファミリーマッチ！', 'きょうだいの意地！', 'きょうだい頂上戦！', 'きょうだい激突！'])
    if k == 'same_circle':
        return cp_combine(
            ['意地とプライドの', '同じ看板の', '手の内知り尽くす', '練習の成果、', '気心知れた', '稽古仲間の', '同じ道場で鍛えた', '切磋琢磨の末の'],
            ['同門対決！', '同門決戦！', '同門バトル！', '内輪の頂上決戦！', '仲間割れマッチ！', '同門の意地！', '道場対抗戦！', 'クラブ内頂上戦！'])
    if k == 'same_attr':
        a = rel.get('attr')
        return cp_combine(
            ['同業対決、', '手練れ同士の', '切れ味対決、', '経験と経験の', '似た者同士の', '玄人対決、', '駆け引き光る', '読み合い上等'],
            [f'{a}対決！', f'{a}マッチ！', f'{a}の意地！', f'{a}激突！', f'{a}バトル！', f'{a}戦！', f'{a}頂上戦！', f'{a}決戦！'])
    if k == 'cross_circle':
        return cp_combine(
            ['威信を懸けた', '看板を背負う', '越境してきた', '名誉を懸けた', '二つの会が交わる', '会の誇りを懸けた', '遠征してきた', '初参戦の意地'],
            ['サークル対抗戦！', 'クラブ対抗マッチ！', '越境対決！', '他流試合！', '交流戦の頂点！', 'クラブ代表対決！', '他クラブとの激突！', '対抗戦の華！'])
    return ''


# 優先0: グランドファイナル×関係性の合成文
# ⚠️ w（関係性の呼称）は「きょうだい」等で最大5文字になりうる。head/tailの文字数上限は
#    w+head+tailの合計が17文字以内になるよう逆算して設定している（head<=3, tail<=9）。
def cp_grand_final_with_relation(rel):
    w = cp_rel_word(rel)
    if not w:
        return ''
    return cp_combine(
        [f'{w}で挑む', f'{w}が挑む', f'{w}対決の', f'{w}が競う', f'{w}が結ぶ', f'{w}が刻む', f'{w}の意地', f'{w}の証', f'{w}を懸け', f'{w}が輝く', f'{w}の頂点', f'{w}が導く'],
        ['運命の決勝戦！', '大会最後の一戦！', '栄冠を懸けた戦い！', '最終決戦！', '運命の決勝！', '頂上決戦！', '大一番の舞台！', '全てを懸けた戦い！', '栄光の頂点戦！', '王座を懸けた一戦！', '大会最終決戦！', '運命のファイナル！'])


# 優先2: ステージ
# ⚠️ 「決勝戦」「最終決戦」等の“大会の決着”を意味する語は GRAND FINAL / GF RESET 専用。
#    WB FINAL / LB FINAL はブラケット内の準決勝相当なので、必ず固有名で呼ぶこと。
#    判定順を変えないこと（LB FINAL は LOSER の一般判定より先に評価する必要がある）。
# ⚠️ LOSER/敗者専用の分岐は撤去済み（意図的）。LB戦は WB と同じく
#    優先3(H2H)→優先4(戦績)→優先5(初対戦)のチェーンへ流す。
#    「サバイバル」「敗者復活」「背水」「崖っぷち」「生き残り」等の敗者専用語は
#    他のプールにも追加しないこと（敗者戦だけを見下す煽りが単調化する原因だったため）。
def cp_from_stage(label):
    raw = str(label or '')
    s = raw.upper()
    if 'GRAND FINAL' in s or 'GF RESET' in s:
        return cp_combine(
            ['栄冠を懸けた', '頂点を賭けた', '全てを出し切る', '王座を懸けた', '誰もが待った', '大会最後の', '双方譲れぬ', '沸騰必至の', '一世一代の', '会場が震える', '全てが決まる', '緊張感高まる'],
            ['グランドファイナル！', 'ファイナルバトル！', '頂上決戦！', '最終決戦！', '大一番！', '運命の一戦！', '栄光の瞬間！', '大会の頂点！', '王座決定戦！', '決着の時！', '最高の舞台！', '大会最終戦！'])
    if 'WB FINAL' in s:
        return cp_combine(
            ['無敗対決！', '土をつける、', '一敗も許されぬ', 'GF直行の権利', '勝てば頂上戦、', '無敗を懸けた', '後がない', '勝者だけが進む', '両者無敗の', '実力証明の', '負け知らずの', '突き進む両雄の'],
            ['ウィナーズ決戦！', 'ウィナーズ最終決戦！', 'ウィナーズ頂点争い！', 'ウィナーズの大一番！', 'ウィナーズ突破戦！', 'ウィナーズの意地！', '無敗対決の行方！', 'ウィナーズ王手！', '頂点まであと一勝！', 'GFへの切符争い！', 'ウィナーズ頂上戦！', '無敗継続の一戦！'])
    if 'LB FINAL' in s:
        return cp_combine(
            ['後がない', '這い上がりし者', '最後の一枠へ', 'GFへの関門', '生き残るは一人', '敗者復活の切符', '崖っぷちの両者', '泥沼を抜けた', 'ラストチャンス', '生存を懸けた', '落ちれば終わり', '執念の生還'],
            ['ルーザーズ決戦！', 'ルーザーズ最終決戦！', 'ルーザーズ生存戦！', 'ルーザーズの大一番！', 'ルーザーズ突破戦！', 'ルーザーズの意地！', '敗者復活の行方！', 'ルーザーズ王手！', 'GFへの切符争い！', 'ラストチャンス決戦！', 'ルーザーズ頂上戦！', '崖っぷちの一戦！'])
    if '3RD PLACE' in s or '3位' in raw:
        return cp_combine(
            ['表彰台を懸けた', '意地と誇りの', '最後の一枠を争う', '譲れない', '締めくくりの', '三番手を懸けた', '意地の三番勝負', '涙も笑いも懸けた', '負けられぬ三番手', '最後の表彰台へ', '意地の三択', '締めの一戦、'],
            ['3位決定戦！', '表彰台争い！', 'ブロンズマッチ！', '最後の一戦！', '意地の一番！', '意地の三位戦！', '涙の表彰台！', '三番手決定戦！', '締めの一番！', '表彰台への切符！', '意地の一戦！', '最後の意地戦！'])
    return ''


# 優先3: H2H
def cp_from_h2h(w1, w2):
    if w1 is None or w2 is None:
        return ''
    if w1 >= 1 and w2 >= 1:
        return cp_combine(
            ['宿命の', '何度目かの', '決着つかぬ', '因縁深き', '譲れぬ', '幾度となき', '積年の', '決着を急ぐ', '三度目の', '火花散る', '伝説の再演、', '雌雄を決する'],
            ['ライバル対決！', '再戦マッチ！', '好敵手対決！', '決着戦！', 'リマッチ！', 'ライバル決戦！', '因縁の一戦！', '決着マッチ！', '宿命の激突！', '再戦の行方！', '因縁再燃！', '決戦の再来！'])
    if w1 >= 1 or w2 >= 1:
        return cp_combine(
            ['執念の', '借りを返す', '雪辱を期す', '過去を塗り替える', '牙を研いだ', '雪辱に燃える', '借りは返す、', '牙を磨いた', '再挑戦の', '捲土重来の', '意地を見せる', '汚名返上の'],
            ['リベンジマッチ！', '仕返しの一戦！', '再戦！', '挑戦状！', '返り討ちなるか！', 'リベンジ戦！', '雪辱の一戦！', '再戦の行方！', '意地の一戦！', '牙を剥く一戦！', '借りを返す時！', '再戦成るか！'])
    return ''


# 優先5: 初顔合わせ（関係性・ステージ・H2H・戦績のいずれでも決まらない場合の最終手段）
def cp_first_meeting():
    return cp_combine(
        ['予測不能の', '手の内知らぬ', '未知数の', 'データなしの', '互いに初めての', '情報戦の', '初対面同士の', '手探りの', '未体験の', '見えない相性の', 'ぶっつけ本番の', '互いに探り合う'],
        ['初顔合わせ！', 'ファーストマッチ！', '初対決！', 'ぶつかり合い！', '未知の激突！', '初対面の激突！', '未知との遭遇！', '手探りの一戦！', 'データなき戦い！', '読み合いの初陣！', '未体験の激突！', '初陣を飾れるか！'])


# 優先4: 戦績
def cp_from_stats(p1, p2):
    t1, t2 = cp_rank_tier(p1.get('rank')), cp_rank_tier(p2.get('rank'))
    if t1 is None or t2 is None:
        return ''
    s1, s2 = p1.get('currentStats') or {}, p2.get('currentStats') or {}
    r1, r2 = cp_rate_num(s1.get('rate')), cp_rate_num(s2.get('rate'))
    bp1 = _to_num(s1.get('power'))
    bp2 = _to_num(s2.get('power'))
    both_top = (t1 >= 3 and t2 >= 3) or (r1 is not None and r2 is not None and r1 >= 60 and r2 >= 60)
    if both_top:
        return cp_combine(
            ['トップランカーの', '上位陣が激突する', '実力者同士の', '高ランク同士の', '会を代表する', '選ばれし者達の', '名だたる強者の', '頂点に立つ者の', '王者候補同士の', '格の違いなき', '一流対決、', '折り紙付き同士の'],
            ['頂上決戦！', 'ハイレベルマッチ！', '頂点争い！', 'エリート対決！', '最高峰の一戦！', '頂上対決！', '王者の風格！', '頂点への布石！', '実力伯仲！', '最強決定戦！', '格の違いなし！', '頂上の激突！'])
    if abs(t1 - t2) >= 2 or abs(bp1 - bp2) >= 3000:
        return cp_combine(
            ['魅せろ、', '金星を狙う', '下剋上を狙う', '格上に挑む', '常識を覆す', '風穴を開ける', '一発逆転狙う', '波乱を呼ぶ', '格差を覆す', '挑戦者の意地', '下克上なるか', '伏兵の一撃'],
            ['ジャイアントキリング！', '番狂わせ！', '下剋上マッチ！', '挑戦者の一撃！', 'アップセット！', '波乱の幕開け！', '金星ゲット！', '伏兵参上！', '格上撃破！', '大金星なるか！', '常識崩し！', '挑戦者の一矢！'])
    return cp_combine(
        ['実力伯仲の', '互角の', '甲乙つけがたい', '五分と五分の', '譲らぬ両者の', '一歩も譲らぬ', '紙一重の', '一歩も引かぬ', '伯仲同士の', '互角すぎる', '決着つかぬ', '実力互角の'],
        ['ガチンコバトル！', '真っ向勝負！', '総力戦！', '一騎打ち！', '大接戦必至！', '大熱戦必至！', '紙一重の勝負！', '互角の激突！', '一進一退！', '接戦必至！', '手に汗握る一戦！', '死闘必至！'])


def _to_num(v):
    """JS の Number(x) || 0 相当"""
    try:
        f = float(v)
    except (TypeError, ValueError):
        return 0
    return 0 if f != f else f


if __name__ == '__main__':
    random.seed(0)
    fails = []

    def check(name, cond, detail=''):
        print(('OK  ' if cond else 'NG  ') + name + (f' {detail}' if detail else ''))
        if not cond:
            fails.append(name)

    # ランク・勝率のパース
    check('rank_tier', [cp_rank_tier(x) for x in ['--', '', None, 'X', '39', '40', '59', '60', '79', '80', '89', '90', 'abc']]
          == [None, None, None, 5, 0, 1, 1, 2, 2, 3, 3, 4, None][:12] + [None])
    check('rate_num', [cp_rate_num(x) for x in ['65.5%', '60', '', None, 'x']] == [65.5, 60.0, None, None, None])

    # GF×関係性: w+head+tail は 17 文字以内（コメントの設計制約）
    longest = 0
    for rel in [{'kind': 'spouse'}, {'kind': 'parent_child'}, {'kind': 'parent_child', 'motherSide': True},
                {'kind': 'sibling'}, {'kind': 'same_circle'}, {'kind': 'cross_circle'}, {'kind': 'same_attr', 'attr': '格ゲーマー'}]:
        for _ in range(300):
            longest = max(longest, len(cp_grand_final_with_relation(rel)))
    check('GF×関係性 最大文字数 <= 17', longest <= 17, f'(最大 {longest})')

    # 全分岐が空文字を返さない
    rels = [{'kind': k} for k in ['spouse', 'parent_child', 'sibling', 'same_circle', 'cross_circle']] + [{'kind': 'same_attr', 'attr': '格ゲーマー'}]
    check('関係性 全種で非空', all(cp_from_relation(r) for r in rels))
    check('ステージ 全種で非空', all(cp_from_stage(x) for x in ['Grand Final', 'GF RESET', 'WB FINAL', 'LB FINAL', '3RD PLACE', '3位決定戦']))
    check('通常ラウンドは空', cp_from_stage('W2-1') == '' and cp_from_stage(None) == '')
    check('H2H 3分岐', bool(cp_from_h2h(1, 1)) and bool(cp_from_h2h(1, 0)) and cp_from_h2h(0, 0) == '' and cp_from_h2h(None, 1) == '')
    check('初顔合わせ 非空', bool(cp_first_meeting()))

    # 戦績: 3分岐に入ること
    top = {'rank': '90', 'currentStats': {'rate': '70%', 'power': 12000}}
    low = {'rank': '30', 'currentStats': {'rate': '20%', 'power': 10000}}
    mid = {'rank': '50', 'currentStats': {'rate': '40%', 'power': 10500}}
    check('戦績 トップ同士', cp_from_stats(top, top) != '')
    check('戦績 格差', cp_from_stats(top, low) != '')
    check('戦績 互角', cp_from_stats(mid, mid) != '')
    check('戦績 ランク欠損は空', cp_from_stats({'rank': '--'}, mid) == '')

    # 直近履歴の重複回避
    _catchphrase_history.clear()
    outs = [cp_combine(['a', 'b'], ['x', 'y']) for _ in range(4)]
    check('履歴リング上限', len(_catchphrase_history) <= CATCHPHRASE_HISTORY_LIMIT)

    print(f'\n{len(fails)} 件失敗' if fails else '\n全チェック OK')
    raise SystemExit(1 if fails else 0)
