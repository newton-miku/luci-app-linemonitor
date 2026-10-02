#!/bin/sh
# 确认这个固件的 LuCI 是「客户端 JS 视图」模式，并找出正确的视图文件位置
echo "=== /www/luci-static/resources/view/ 目录 ==="
ls /www/luci-static/resources/view/ 2>/dev/null | head -60
echo
echo "=== ttyd 的视图文件（menu.d 里 path=ttyd/term） ==="
ls -l /www/luci-static/resources/view/ttyd/ 2>/dev/null || echo "no ttyd dir"
echo
echo "=== ttyd/term.js 内容（客户端视图模板） ==="
cat /www/luci-static/resources/view/ttyd/term.js 2>/dev/null | head -40
echo
echo "=== 是否存在 htm 视图目录 ==="
ls /usr/lib/lua/luci/view/ | grep -iE 'ttyd|wol' || echo "no ttyd/wol in /usr/lib/lua/luci/view"
echo
echo "=== luci.js 中 view 加载逻辑 ==="
grep -o 'resources/view/[^"]*' /www/luci-static/resources/luci.js 2>/dev/null | head -5
echo
echo "=== Argon 主题目录 ==="
ls /www/luci-static/ 2>/dev/null
