#!/bin/bash
# 업데이트 피드(appcast.xml)를 만든다. 항목은 하나(이 버전)이고, zip 은 Sparkle 의 sign_update 로 로그인 키체인의 개인키로 서명한다.
#   tools/make-appcast.sh <zip> <버전> <zip 다운로드 주소> <릴리스 노트(.md)> <최소 macOS> <출력 appcast.xml>
# release.sh 와 업데이트 시험이 같은 스크립트를 쓴다. 처음 서명할 때 키체인이 sign_update 의 접근 허용을 물으면 '항상 허용' 을 고른다.
set -euo pipefail
zip=${1:?사용: make-appcast.sh <zip> <버전> <다운로드 주소> <노트.md> <최소 macOS> <출력.xml>}
version=${2:?}
url=${3:?}
notes=${4:?}
min_os=${5:?}
out=${6:?}
[[ -f $zip && -f $notes ]] || { echo "make-appcast: zip 또는 릴리스 노트가 없습니다" >&2; exit 1; }
[[ $url == https://* || $url == http://127.0.0.1:* ]] || { echo "make-appcast: 다운로드 주소가 https 가 아닙니다(시험용 127.0.0.1 만 예외): $url" >&2; exit 1; }

sparkle=$("$(dirname "$0")/sparkle.sh")
signature=$("$sparkle/bin/sign_update" -p "$zip")
[[ $signature =~ ^[A-Za-z0-9+/]{86}==$ ]] || { echo "make-appcast: 서명 형식이 이상합니다: $signature" >&2; exit 1; }
length=$(/usr/bin/stat -f %z "$zip")
pub_date=$(LC_ALL=C /bin/date -u '+%a, %d %b %Y %H:%M:%S +0000')

# 릴리스 노트(CHANGELOG 섹션, 마크다운)를 간단한 HTML 로 바꾼다: ### 소제목, - 목록, **굵게**, `코드`. 먼저 &, <, > 를 이스케이프한다.
html=$(/usr/bin/sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$notes" | /usr/bin/awk '
  /^### / { if (list) { print "</ul>"; list = 0 } print "<h4>" substr($0, 5) "</h4>"; next }
  /^- /   { if (!list) { print "<ul>"; list = 1 } print "<li>" substr($0, 3) "</li>"; next }
  /^[[:space:]]*$/ { next }
  { if (list) { print "</ul>"; list = 0 } print "<p>" $0 "</p>" }
  END { if (list) print "</ul>" }
' | /usr/bin/sed -E -e 's/\*\*([^*]+)\*\*/<b>\1<\/b>/g' -e 's/`([^`]+)`/<code>\1<\/code>/g' \
      -e 's/\[([^]]+)\]\((https:\/\/[^) ]+)\)/<a href="\2">\1<\/a>/g')
[[ $html != *"]]>"* ]] || { echo "make-appcast: 릴리스 노트에 ]]> 가 있습니다" >&2; exit 1; }

cat > "$out" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>QuickStream</title>
        <item>
            <title>QuickStream $version</title>
            <pubDate>$pub_date</pubDate>
            <sparkle:version>$version</sparkle:version>
            <sparkle:shortVersionString>$version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$min_os</sparkle:minimumSystemVersion>
            <description><![CDATA[$html]]></description>
            <enclosure url="$url" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
        </item>
    </channel>
</rss>
EOF
/usr/bin/xmllint --noout "$out"
