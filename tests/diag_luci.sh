#!/bin/sh
# 排查 LuCI 菜单机制：确认 menu.d JSON 是否被 Lua 版 dispatcher 消费
echo "=== dispatcher.lua 中 menu.d / create_tree 相关 ==="
grep -n 'menu\.d\|menu_json\|create_tree\|firstchild\|action' /usr/lib/lua/luci/dispatcher.lua | head -40
echo
echo "=== controller 里匹配 ttyd/wol/statistics/mwan ==="
ls /usr/lib/lua/luci/controller/ | grep -iE 'ttyd|wol|statistics|mwan'
echo
echo "=== controller 总数 ==="
ls /usr/lib/lua/luci/controller/ | wc -l
echo
echo "=== menu.d 清单 ==="
ls /usr/share/luci/menu.d/
echo
echo "=== luci-indexcache 内容片段（找 linemon） ==="
grep -c 'linemon' /tmp/luci-indexcache.*.json 2>/dev/null || echo "0"
grep -o 'linemon[^"]*' /tmp/luci-indexcache.*.json 2>/dev/null | head -10 || true
