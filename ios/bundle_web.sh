#!/bin/sh
# Xcode の Run Script から呼ばれる。リポジトリ直下の score.html と素材をアプリに同梱する。
# score.html の原本は1つだけに保ち、ここでは「アプリに入れるコピー」だけを書き換える。
#
# 書き換え内容（アプリ版のみ。ブラウザ版の score.html は CDN のまま）:
#  - PeerJS / qrcodejs を CDN ではなく同梱ファイル（ios/vendor/）から読む
#    → 会場の Wi-Fi が「つながっているのにネットに出られない」状態だと、<head> の CDN 読み込みで
#      ページの描画が止まり、HUD が出ないまま固まる（タスクキルしても同じ）。2026-10 に実機で発生
#  - Google Fonts を描画を止めない読み込みにする（届くまでは代替フォントで表示）
set -e
SRC="${SRCROOT}/.."
DST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/web"
mkdir -p "${DST}/font" "${DST}/vendor"

PEERJS_CDN='https://unpkg.com/peerjs@1.5.2/dist/peerjs.min.js'
QRCODE_CDN='https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js'
FONTS_LINK='&display=swap" rel="stylesheet">'

for needle in "${PEERJS_CDN}" "${QRCODE_CDN}" "${FONTS_LINK}"; do
  if ! grep -qF "${needle}" "${SRC}/score.html"; then
    echo "error: score.html に「${needle}」が見つかりません。CDN の URL を変えた場合は ios/vendor/ のファイルと ios/bundle_web.sh を合わせて更新してください" >&2
    exit 1
  fi
done

sed -e "s#${PEERJS_CDN}#vendor/peerjs.min.js#" \
    -e "s#${QRCODE_CDN}#vendor/qrcode.min.js#" \
    -e "s#&display=swap\" rel=\"stylesheet\">#\&display=swap\" rel=\"stylesheet\" media=\"print\" onload=\"this.media='all'\">#" \
    "${SRC}/score.html" > "${DST}/score.html"

if grep -qE 'unpkg\.com|cdnjs\.cloudflare\.com' "${DST}/score.html"; then
  echo "error: 同梱版 score.html に CDN の読み込みが残っています（ios/bundle_web.sh を確認）" >&2
  exit 1
fi

cp "${SRCROOT}/vendor/peerjs.min.js" "${SRCROOT}/vendor/qrcode.min.js" "${DST}/vendor/"
cp "${SRC}/maintitle_white.png" "${SRC}/torabo_logo.png" "${DST}/"
cp "${SRCROOT}/mirror.html" "${DST}/mirror.html"
cp "${SRC}/font/DSEG7Classic-BoldItalic.ttf" "${DST}/font/"
