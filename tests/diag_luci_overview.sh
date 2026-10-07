#!/bin/sh
echo "=== 1. quickstart / overview 路由定义 ==="
grep -rn "quickstart" /usr/lib/lua/luci/controller/ 2>/dev/null | head -20
echo
echo "=== 2. 视图文件 ==="
ls -la /usr/lib/lua/luci/view/admin_status/ 2>/dev/null
ls -la /www/luci-static/resources/view/status/ 2>/dev/null
echo
echo "=== 3. 谁在读网卡计数 ==="
grep -rln "proc/net/dev" /www/luci-static/resources/ /usr/lib/lua/luci/ 2>/dev/null | head -30
grep -rln "statistics/rx_bytes\|statistics/tx_bytes" /www/luci-static/resources/ /usr/lib/lua/luci/ 2>/dev/null | head -30
echo
echo "=== 4. 谁在读 mtk / hnat / esw / hwnat ==="
grep -rln "mtketh" /www/ /usr/lib/lua/ 2>/dev/null | head -20
grep -rln "esw_cnt\|hwnat\|hnat" /www/ /usr/lib/lua/ 2>/dev/null | head -20
echo
echo "=== 5. luci-rpc / network 相关 ==="
ls -la /usr/lib/lua/luci/ 2>/dev/null | head -30
echo "--- rpcd 脚本 ---"
ls -la /usr/libexec/rpcd/ 2>/dev/null
echo
echo "=== 6. 看板 iframe 之外，overview 页面里带宽相关字样 ==="
grep -rn "带宽\|实时流量\|traffic" /usr/lib/lua/luci/view/admin_status/ 2>/dev/null | head -20
