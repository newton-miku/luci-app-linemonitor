echo "=== 内置上游设备相关 LuCI app ==="
ls /usr/share/luci/menu.d/ 2>/dev/null | grep -iE 'modem|cell|at|wdm|wt|mifi|4g|5g|nradio' 
echo "--- 菜单项标题 ---"
grep -l -iE '上游设备|内置|modem|cellular' /usr/share/luci/menu.d/*.json 2>/dev/null
echo
echo "=== 相关已安装包 ==="
opkg list-installed 2>/dev/null | grep -iE 'modem|cell|at-sd|atsd|wtmodem|nradio|atcmd|mifi' | head -20
echo
echo "=== /etc/config 下的相关配置 ==="
ls -la /etc/config/ | grep -iE 'modem|cell|at|wdm|wt|mifi|notif|push|alert'
echo
echo "=== 搜 notif/push/webhook/bark/serverchan/telegram 关键字 ==="
grep -ril -E 'notif|webhook|bark|serverchan|pushplus|telegram|dingtalk|feishu' /etc/config/ 2>/dev/null | head
echo
echo "=== 上游设备 pps 相关脚本 ==="
grep -rl -iE 'pps' /usr/bin /usr/sbin /usr/lib/lua/luci 2>/dev/null | head -20