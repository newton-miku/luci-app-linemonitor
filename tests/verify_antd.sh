#!/bin/sh
echo "=== /www/lm/ ==="
ls -l /www/lm/
echo "=== /www/lm/lib/ ==="
ls -l /www/lm/lib/
echo "=== HTTP ==="
for u in /lm/line.html /lm/lib/antd.dark.min.css /lm/config.json /lm/history.log \
         /luci-static/resources/view/linemon/status.js; do
    printf '%s -> ' "$u"
    curl -s -o /dev/null -w '%{http_code} %{size_download}\n' "http://127.0.0.1$u"
done
echo "=== 看板是否引用 antd ==="
grep -c 'antd.dark.min.css' /www/lm/line.html
grep -o '<title>[^<]*</title>' /www/lm/line.html
