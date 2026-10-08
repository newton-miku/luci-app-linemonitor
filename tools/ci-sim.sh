#!/bin/sh
# 本机模拟一遍 CI 的组装与自检（不跑 npm，用已有的 web/dist）。
# 用法：sh tools/ci-sim.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

OUT=/tmp/lm-sim
rm -rf "$OUT"
mkdir -p "$OUT"

echo "=== 1. 铺前端产物 ==="
rm -rf deploy/www/lm/app
mkdir -p deploy/www/lm/app
cp -r web/dist/. deploy/www/lm/app/
find deploy/www/lm/app -type f | sort

echo
echo "=== 2. 拉第三方库 ==="
sh tools/fetch-vendor.sh >/dev/null
ls deploy/www/lm/lib

echo
echo "=== 3. 打包 ==="
tar -czf "$OUT/linemon-sim.tar.gz" deploy tools tests README.md LICENSE
ls -l "$OUT/linemon-sim.tar.gz"

echo
echo "=== 4. 关键文件自检 ==="
MUST="deploy/install.sh
deploy/usr/bin/line_monitor.sh
deploy/usr/bin/line_daemon.sh
deploy/usr/bin/lm_alert.sh
deploy/usr/bin/lm_rate.sh
deploy/usr/bin/lm_config_json.sh
deploy/usr/bin/tcp_stream.sh
deploy/etc/line-monitor/targets.conf
deploy/etc/init.d/linemon
deploy/www/lm/app/index.html
deploy/www/lm/line.html
deploy/www/lm/config.html
deploy/www/lm/lib/antd.dark.min.css
deploy/www/cgi-bin/lm-config
deploy/www/cgi-bin/lm-rate
deploy/www/luci-static/resources/view/linemon/status.js
deploy/www/luci-static/resources/view/linemon/config.js
deploy/usr/share/luci/menu.d/luci-app-linemon.json
deploy/usr/share/rpcd/acl.d/luci-app-linemon.json"
rc=0
n=0
for m in $MUST; do
    n=$((n + 1))
    if tar -tzf "$OUT/linemon-sim.tar.gz" | grep -qx "$m"; then
        echo "  OK    $m"
    else
        echo "  MISS  $m"
        rc=1
    fi
done
echo "自检 $n 项，缺失 $([ $rc -eq 0 ] && echo 0 || echo 有)"
exit $rc
