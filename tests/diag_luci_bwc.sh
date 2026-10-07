#!/bin/sh
echo "=== luci-bwc: 关键路径字符串 ==="
strings /usr/bin/luci-bwc | grep -iE 'hnat|mtk|esw|all_entry|qdma|/sys/|/proc/' | sort -u
echo
echo "=== luci-bwc: 采样文件 / 状态 ==="
strings /usr/bin/luci-bwc | grep -iE 'var/|pid|if/%s|seq|freq|interval' | sort -u
echo
echo "=== /var/lib/luci-bwc ==="
ls -la /var/lib/luci-bwc/ 2>/dev/null
ls -la /var/lib/luci-bwc/if/ 2>/dev/null | head -20
echo
echo "=== 实测：luci-bwc 各模式输出 ==="
echo "--- eth0 (默认) ---"
luci-bwc 2>/dev/null | head -20
echo "--- -i eth0 ---"
luci-bwc -i eth0 2>&1 | head -20
echo "--- -i BLUE4 ---"
luci-bwc -i BLUE4 2>&1 | head -20
echo "--- -i pppoe-wan2 ---"
luci-bwc -i pppoe-wan2 2>&1 | head -20
echo "--- -i br-lan ---"
luci-bwc -i br-lan 2>&1 | head -20