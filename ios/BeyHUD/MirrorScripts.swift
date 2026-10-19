import Foundation

/// スマホ側の score.html に差し込む「画面の変化を HDMI 側へ送る」スクリプト。
///
/// score.html 自体は変えない。HDMI 側（mirror.html）は PeerJS などのロジックを持たず、
/// ここで送られる DOM の変化（要素の追加・削除・属性・文字・入力値・スクロール）をそのまま再現するだけ。
/// 外部ディスプレイが無い間は `__beyMirrorEnable(false)` のままで、MutationObserver も動かさない（負荷ゼロ）。
///
/// メッセージ（JSON 文字列）:
///   {k:'init', vw, vh, html, head, body}  全体（接続時・再同期時）
///   {k:'m', ops:[...]}                     差分。op は c(子の並び) / a(属性) / t(文字) / v(入力値) / s(スクロール)
enum MirrorScripts {
    static let leader = #"""
    (function () {
      'use strict';
      if (window.__beyMirrorEnable) return;
      var H = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.beyMirror;
      if (!H) return;

      var ids = new WeakMap();
      var sent = new WeakSet();     // HDMI 側へ送り済みのノード
      var nextId = 1;
      var mo = null, pollTimer = null;
      var lastVals = new WeakMap();

      function idOf(n) { var i = ids.get(n); if (!i) { i = nextId++; ids.set(n, i); } return i; }
      function post(o) { try { H.postMessage(JSON.stringify(o)); } catch (e) {} }
      function attrsOf(el) {
        var a = {};
        for (var i = 0; i < el.attributes.length; i++) {
          var at = el.attributes[i];
          if (/^on/i.test(at.name)) continue;      // インラインのイベントハンドラは複製しない
          a[at.name] = at.value;
        }
        return a;
      }
      function isField(el) { var t = el.localName; return t === 'input' || t === 'textarea' || t === 'select'; }
      function fieldVal(el) { return (el.type === 'checkbox' || el.type === 'radio') ? el.checked : el.value; }

      // ノードを、HDMI 側で作り直せる形（JSON）にする。script は複製しない。
      function ser(n) {
        var t = n.nodeType;
        if (t === 3) { sent.add(n); return { t: 3, i: idOf(n), v: n.data }; }
        if (t !== 1) return null;
        var tag = n.localName;
        if (tag === 'script' || tag === 'noscript') return null;
        sent.add(n);
        var o = { t: 1, i: idOf(n), n: tag, a: attrsOf(n), c: [] };
        if (n.namespaceURI !== 'http://www.w3.org/1999/xhtml') o.ns = n.namespaceURI;
        for (var c = n.firstChild; c; c = c.nextSibling) { var s = ser(c); if (s) o.c.push(s); }
        if (isField(n)) {
          var v = fieldVal(n);
          if (typeof v === 'boolean') o.chk = v; else o.val = v;
          lastVals.set(n, v);
        }
        return o;
      }
      function unsent(n) {
        sent.delete(n);
        for (var c = n.firstChild; c; c = c.nextSibling) unsent(c);
      }

      function snapshot() {
        sent = new WeakSet();
        var de = document.documentElement, head = document.head, body = document.body;
        sent.add(de); sent.add(head); sent.add(body);
        var msg = {
          k: 'init', vw: window.innerWidth, vh: window.innerHeight,
          html: { i: idOf(de), a: attrsOf(de) },
          head: { i: idOf(head), a: attrsOf(head), c: [] },
          body: { i: idOf(body), a: attrsOf(body), c: [] }
        };
        var c, s;
        for (c = head.firstChild; c; c = c.nextSibling) { s = ser(c); if (s) msg.head.c.push(s); }
        for (c = body.firstChild; c; c = c.nextSibling) { s = ser(c); if (s) msg.body.c.push(s); }
        post(msg);
      }

      function onMut(recs) {
        var parents = new Set(), attrs = new Map(), texts = new Set();
        recs.forEach(function (r) {
          var tg = r.target;
          if (r.type === 'childList') {
            for (var i = 0; i < r.removedNodes.length; i++) { var rn = r.removedNodes[i]; if (!rn.isConnected) unsent(rn); }
            if (sent.has(tg)) parents.add(tg);
          } else if (r.type === 'attributes') {
            if (sent.has(tg)) { var m = attrs.get(tg); if (!m) { m = new Set(); attrs.set(tg, m); } m.add(r.attributeName); }
          } else if (r.type === 'characterData') {
            if (sent.has(tg)) texts.add(tg);
          }
        });
        var out = [];
        // 子の並び: 送り済みの子は {r:id} で参照し、新しい子だけ全体を送る
        parents.forEach(function (p) {
          if (!p.isConnected) return;
          var c = [];
          for (var ch = p.firstChild; ch; ch = ch.nextSibling) {
            var s = sent.has(ch) ? { r: idOf(ch) } : ser(ch);
            if (s) c.push(s);
          }
          out.push({ k: 'c', p: idOf(p), c: c });
        });
        attrs.forEach(function (names, el) {
          if (!el.isConnected) return;
          names.forEach(function (name) {
            if (/^on/i.test(name)) return;
            out.push({ k: 'a', i: idOf(el), n: name, v: el.getAttribute(name) });
          });
        });
        texts.forEach(function (t) { if (t.isConnected) out.push({ k: 't', i: idOf(t), v: t.data }); });
        if (out.length) post({ k: 'm', ops: out });
      }

      // 入力欄の値は属性ではなくプロパティなので、変化を定期的に拾う（名前欄など）
      function poll() {
        var ops = [];
        var els = document.querySelectorAll('input,textarea,select');
        for (var i = 0; i < els.length; i++) {
          var el = els[i];
          if (!sent.has(el)) continue;
          var v = fieldVal(el);
          if (lastVals.get(el) !== v) { lastVals.set(el, v); ops.push({ k: 'v', i: idOf(el), v: v }); }
        }
        if (ops.length) post({ k: 'm', ops: ops });
      }

      document.addEventListener('scroll', function (e) {
        if (!mo) return;
        var t = e.target;
        if (t && t.nodeType === 1 && sent.has(t)) post({ k: 'm', ops: [{ k: 's', i: idOf(t), x: t.scrollLeft, y: t.scrollTop }] });
      }, true);

      window.addEventListener('resize', function () { if (mo) post({ k: 'vp', w: window.innerWidth, h: window.innerHeight }); });

      window.__beyMirrorEnable = function (on) {
        if (mo) { mo.disconnect(); mo = null; }
        if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
        if (!on) return;
        snapshot();
        mo = new MutationObserver(onMut);
        mo.observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });
        pollTimer = setInterval(poll, 250);
      };
    })();
    """#
}
