function pickRandom(arr){return arr[Math.floor(Math.random()*arr.length)];}
function cpRankTier(rankStr) {
      const s = String(rankStr || '').trim().toUpperCase();
      if (!s || s === '--') return null;
      if (s.startsWith('X')) return 5;
      const n = parseInt(s, 10);
      if (isNaN(n)) return null;
      if (n < 40) return 0;
      if (n < 60) return 1;
      if (n < 80) return 2;
      if (n < 90) return 3;
      return 4;
    }
    function cpRateNum(rateStr) {
      const v = parseFloat(String(rateStr || '').replace('%', ''));
      return isNaN(v) ? null : v;
    }
    // 前半×後半を組み合わせる。直近8件のリングバッファと重複する場合は最大5回まで引き直す
    const _catchphraseHistory = [];
    const CATCHPHRASE_HISTORY_LIMIT = 8;
    function cpCombine(heads, tails) {
      let out = pickRandom(heads) + pickRandom(tails);
      let tries = 0;
      while (_catchphraseHistory.includes(out) && tries < 5) {
        out = pickRandom(heads) + pickRandom(tails);
        tries++;
      }
      _catchphraseHistory.push(out);
      if (_catchphraseHistory.length > CATCHPHRASE_HISTORY_LIMIT) _catchphraseHistory.shift();
      return out;
    }
    // 関係性 → 合成用の短い呼称
    function cpRelWord(rel) {
      if (!rel) return '';
      if (rel.kind === 'spouse') return '夫婦';
      if (rel.kind === 'parent_child') return rel.motherSide ? '母子' : '親子';
      if (rel.kind === 'sibling') return 'きょうだい';
      if (rel.kind === 'same_circle') return '同門';
      if (rel.kind === 'same_attr') return rel.attr;
      if (rel.kind === 'cross_circle') return '他流';
      return '';
    }
    // 優先1: 関係性ベース
    function cpFromRelation(rel) {
      if (!rel) return '';
      if (rel.kind === 'spouse') {
        return cpCombine(
          ['愛と闘志の', '誓いを交わした', '家庭を懸けた', '最も近い好敵手、', '譲れぬ', '公私を懸けた', '阿吽の呼吸で挑む', '日常を持ち込んだ'],
          ['夫婦対決！', '夫婦決戦！', '夫婦バトル！', '夫婦の一戦！', 'カップルマッチ！', '夫婦の意地！', '夫婦ダービー！', '夫婦頂上決戦！']);
      }
      if (rel.kind === 'parent_child') {
        const kin = rel.motherSide ? '母子' : '親子';
        return cpCombine(
          ['血を分けた', '世代を超えた', '絆を懸けた', '受け継がれし', '譲れぬ想いの', '親から子へ', '背中を追いかけた', '血筋が交わる'],
          [`${kin}対決！`, `${kin}決戦！`, `${kin}バトル！`, `${kin}の一戦！`, 'ファミリーマッチ！', `${kin}頂上戦！`, `${kin}の意地！`, `${kin}激突！`]);
      }
      if (rel.kind === 'sibling') {
        return cpCombine(
          ['負けられない', '幼き日からの', '同じ屋根の下、', '譲れぬ意地の', '血で血を洗う', '切磋琢磨してきた', '幼馴染以上の', '同じ血を継ぐ'],
          ['きょうだい対決！', 'きょうだい決戦！', 'きょうだいバトル！', 'きょうだいの一戦！', 'ファミリーマッチ！', 'きょうだいの意地！', 'きょうだい頂上戦！', 'きょうだい激突！']);
      }
      if (rel.kind === 'same_circle') {
        return cpCombine(
          ['意地とプライドの', '同じ看板の', '手の内知り尽くす', '練習の成果、', '気心知れた', '稽古仲間の', '同じ道場で鍛えた', '切磋琢磨の末の'],
          ['同門対決！', '同門決戦！', '同門バトル！', '内輪の頂上決戦！', '仲間割れマッチ！', '同門の意地！', '道場対抗戦！', 'クラブ内頂上戦！']);
      }
      if (rel.kind === 'same_attr') {
        const a = rel.attr;
        return cpCombine(
          ['同業対決、', '手練れ同士の', '切れ味対決、', '経験と経験の', '似た者同士の', '玄人対決、', '駆け引き光る', '読み合い上等'],
          [`${a}対決！`, `${a}マッチ！`, `${a}の意地！`, `${a}激突！`, `${a}バトル！`, `${a}戦！`, `${a}頂上戦！`, `${a}決戦！`]);
      }
      if (rel.kind === 'cross_circle') {
        return cpCombine(
          ['威信を懸けた', '看板を背負う', '越境してきた', '名誉を懸けた', '二つの会が交わる', '会の誇りを懸けた', '遠征してきた', '初参戦の意地'],
          ['サークル対抗戦！', 'クラブ対抗マッチ！', '越境対決！', '他流試合！', '交流戦の頂点！', 'クラブ代表対決！', '他クラブとの激突！', '対抗戦の華！']);
      }
      return '';
    }
    // 優先0: グランドファイナル×関係性の合成文
    // ⚠️ w（関係性の呼称）は「きょうだい」等で最大5文字になりうる。head/tailの文字数上限は
    //    w+head+tailの合計が17文字以内になるよう逆算して設定している（head<=3, tail<=9）。
    function cpGrandFinalWithRelation(rel) {
      const w = cpRelWord(rel);
      if (!w) return '';
      return cpCombine(
        [`${w}で挑む`, `${w}が挑む`, `${w}対決の`, `${w}が競う`, `${w}が結ぶ`, `${w}が刻む`, `${w}の意地`, `${w}の証`, `${w}を懸け`, `${w}が輝く`, `${w}の頂点`, `${w}が導く`],
        ['運命の決勝戦！', '大会最後の一戦！', '栄冠を懸けた戦い！', '最終決戦！', '運命の決勝！', '頂上決戦！', '大一番の舞台！', '全てを懸けた戦い！', '栄光の頂点戦！', '王座を懸けた一戦！', '大会最終決戦！', '運命のファイナル！']);
    }
    // 優先2: ステージ
    // ⚠️ 「決勝戦」「最終決戦」等の“大会の決着”を意味する語は GRAND FINAL / GF RESET 専用。
    //    WB FINAL / LB FINAL はブラケット内の準決勝相当なので、必ず固有名で呼ぶこと。
    //    判定順を変えないこと（LB FINAL は LOSER の一般判定より先に評価する必要がある）。
    // ⚠️ LOSER/敗者専用の分岐は撤去済み（意図的）。LB戦は WB と同じく
    //    優先3(H2H)→優先4(戦績)→優先5(初対戦)のチェーンへ流す。
    //    「サバイバル」「敗者復活」「背水」「崖っぷち」「生き残り」等の敗者専用語は
    //    他のプールにも追加しないこと（敗者戦だけを見下す煽りが単調化する原因だったため）。
    function cpFromStage(label) {
      const s = String(label || '').toUpperCase();
      const raw = String(label || '');
      if (s.includes('GRAND FINAL') || s.includes('GF RESET')) {
        return cpCombine(
          ['栄冠を懸けた', '頂点を賭けた', '全てを出し切る', '王座を懸けた', '誰もが待った', '大会最後の', '双方譲れぬ', '沸騰必至の', '一世一代の', '会場が震える', '全てが決まる', '緊張感高まる'],
          ['グランドファイナル！', 'ファイナルバトル！', '頂上決戦！', '最終決戦！', '大一番！', '運命の一戦！', '栄光の瞬間！', '大会の頂点！', '王座決定戦！', '決着の時！', '最高の舞台！', '大会最終戦！']);
      }
      if (s.includes('WB FINAL')) {
        return cpCombine(
          ['無敗対決！', '土をつける、', '一敗も許されぬ', 'GF直行の権利', '勝てば頂上戦、', '無敗を懸けた', '後がない', '勝者だけが進む', '両者無敗の', '実力証明の', '負け知らずの', '突き進む両雄の'],
          ['ウィナーズ決戦！', 'ウィナーズ最終決戦！', 'ウィナーズ頂点争い！', 'ウィナーズの大一番！', 'ウィナーズ突破戦！', 'ウィナーズの意地！', '無敗対決の行方！', 'ウィナーズ王手！', '頂点まであと一勝！', 'GFへの切符争い！', 'ウィナーズ頂上戦！', '無敗継続の一戦！']);
      }
      if (s.includes('LB FINAL')) {
        return cpCombine(
          ['後がない', '這い上がりし者', '最後の一枠へ', 'GFへの関門', '生き残るは一人', '敗者復活の切符', '崖っぷちの両者', '泥沼を抜けた', 'ラストチャンス', '生存を懸けた', '落ちれば終わり', '執念の生還'],
          ['ルーザーズ決戦！', 'ルーザーズ最終決戦！', 'ルーザーズ生存戦！', 'ルーザーズの大一番！', 'ルーザーズ突破戦！', 'ルーザーズの意地！', '敗者復活の行方！', 'ルーザーズ王手！', 'GFへの切符争い！', 'ラストチャンス決戦！', 'ルーザーズ頂上戦！', '崖っぷちの一戦！']);
      }
      if (s.includes('3RD PLACE') || raw.includes('3位')) {
        return cpCombine(
          ['表彰台を懸けた', '意地と誇りの', '最後の一枠を争う', '譲れない', '締めくくりの', '三番手を懸けた', '意地の三番勝負', '涙も笑いも懸けた', '負けられぬ三番手', '最後の表彰台へ', '意地の三択', '締めの一戦、'],
          ['3位決定戦！', '表彰台争い！', 'ブロンズマッチ！', '最後の一戦！', '意地の一番！', '意地の三位戦！', '涙の表彰台！', '三番手決定戦！', '締めの一番！', '表彰台への切符！', '意地の一戦！', '最後の意地戦！']);
      }
      return '';
    }
    // 優先3: H2H
    function cpFromH2H(w1, w2) {
      if (w1 == null || w2 == null) return '';
      if (w1 >= 1 && w2 >= 1) {
        return cpCombine(
          ['宿命の', '何度目かの', '決着つかぬ', '因縁深き', '譲れぬ', '幾度となき', '積年の', '決着を急ぐ', '三度目の', '火花散る', '伝説の再演、', '雌雄を決する'],
          ['ライバル対決！', '再戦マッチ！', '好敵手対決！', '決着戦！', 'リマッチ！', 'ライバル決戦！', '因縁の一戦！', '決着マッチ！', '宿命の激突！', '再戦の行方！', '因縁再燃！', '決戦の再来！']);
      }
      if (w1 >= 1 || w2 >= 1) {
        return cpCombine(
          ['執念の', '借りを返す', '雪辱を期す', '過去を塗り替える', '牙を研いだ', '雪辱に燃える', '借りは返す、', '牙を磨いた', '再挑戦の', '捲土重来の', '意地を見せる', '汚名返上の'],
          ['リベンジマッチ！', '仕返しの一戦！', '再戦！', '挑戦状！', '返り討ちなるか！', 'リベンジ戦！', '雪辱の一戦！', '再戦の行方！', '意地の一戦！', '牙を剥く一戦！', '借りを返す時！', '再戦成るか！']);
      }
      return '';
    }
    // 優先5: 初顔合わせ（関係性・ステージ・H2H・戦績のいずれでも決まらない場合の最終手段）
    function cpFirstMeeting() {
      return cpCombine(
        ['予測不能の', '手の内知らぬ', '未知数の', 'データなしの', '互いに初めての', '情報戦の', '初対面同士の', '手探りの', '未体験の', '見えない相性の', 'ぶっつけ本番の', '互いに探り合う'],
        ['初顔合わせ！', 'ファーストマッチ！', '初対決！', 'ぶつかり合い！', '未知の激突！', '初対面の激突！', '未知との遭遇！', '手探りの一戦！', 'データなき戦い！', '読み合いの初陣！', '未体験の激突！', '初陣を飾れるか！']);
    }
    // 優先4: 戦績
    function cpFromStats(p1, p2) {
      const t1 = cpRankTier(p1.rank), t2 = cpRankTier(p2.rank);
      if (t1 === null || t2 === null) return '';
      const r1 = cpRateNum(p1.currentStats && p1.currentStats.rate);
      const r2 = cpRateNum(p2.currentStats && p2.currentStats.rate);
      const bp1 = Number(p1.currentStats && p1.currentStats.power) || 0;
      const bp2 = Number(p2.currentStats && p2.currentStats.power) || 0;
      const bothTop = (t1 >= 3 && t2 >= 3) || (r1 != null && r2 != null && r1 >= 60 && r2 >= 60);
      if (bothTop) {
        return cpCombine(
          ['トップランカーの', '上位陣が激突する', '実力者同士の', '高ランク同士の', '会を代表する', '選ばれし者達の', '名だたる強者の', '頂点に立つ者の', '王者候補同士の', '格の違いなき', '一流対決、', '折り紙付き同士の'],
          ['頂上決戦！', 'ハイレベルマッチ！', '頂点争い！', 'エリート対決！', '最高峰の一戦！', '頂上対決！', '王者の風格！', '頂点への布石！', '実力伯仲！', '最強決定戦！', '格の違いなし！', '頂上の激突！']);
      }
      if (Math.abs(t1 - t2) >= 2 || Math.abs(bp1 - bp2) >= 3000) {
        return cpCombine(
          ['魅せろ、', '金星を狙う', '下剋上を狙う', '格上に挑む', '常識を覆す', '風穴を開ける', '一発逆転狙う', '波乱を呼ぶ', '格差を覆す', '挑戦者の意地', '下克上なるか', '伏兵の一撃'],
          ['ジャイアントキリング！', '番狂わせ！', '下剋上マッチ！', '挑戦者の一撃！', 'アップセット！', '波乱の幕開け！', '金星ゲット！', '伏兵参上！', '格上撃破！', '大金星なるか！', '常識崩し！', '挑戦者の一矢！']);
      }
      return cpCombine(
        ['実力伯仲の', '互角の', '甲乙つけがたい', '五分と五分の', '譲らぬ両者の', '一歩も譲らぬ', '紙一重の', '一歩も引かぬ', '伯仲同士の', '互角すぎる', '決着つかぬ', '実力互角の'],
        ['ガチンコバトル！', '真っ向勝負！', '総力戦！', '一騎打ち！', '大接戦必至！', '大熱戦必至！', '紙一重の勝負！', '互角の激突！', '一進一退！', '接戦必至！', '手に汗握る一戦！', '死闘必至！']);
    }
    // 統括：優先0→1→2→3→4の順に評価し、最初に得られた1文を返す
    
module.exports = { cpFromRelation, cpGrandFinalWithRelation, cpFromStage, cpFromH2H, cpFirstMeeting, cpFromStats, cpCombine };