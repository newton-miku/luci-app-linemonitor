#!/bin/sh
# 对比：能正常显示在侧栏的服务类 app 的 menu.d 写法 vs linemon
echo "=== ls menu.d ==="
ls /usr/share/luci/menu.d/

echo
echo "=== wol (单层 view, 正常显示) ==="
cat /usr/share/luci/menu.d/luci-app-wol.json 2>/dev/null

echo
echo "=== ttyd (firstchild 父 + 子, 对照) ==="
cat /usr/share/luci/menu.d/luci-app-ttyd.json 2>/dev/null

echo
echo "=== mosdns (多子项, 正常显示) ==="
cat /usr/share/luci/menu.d/luci-app-mosdns.json 2>/dev/null

echo
echo "=== statistics (多子项) ==="
cat /usr/share/luci/menu.d/luci-app-statistics.json 2>/dev/null | head -40

echo
echo "=== 侧栏里 ttyd 有没有出现? 查 header 渲染依赖 ==="
ls -l /usr/lib/lua/luci/view/header.htm 2>/dev/null
