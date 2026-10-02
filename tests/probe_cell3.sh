echo "=== luci-app-ModemATSD 安装的文件 ==="
opkg files luci-app-ModemATSD 2>/dev/null | head -40
echo
echo "=== luci-app-WTModem 安装的文件 ==="
opkg files luci-app-WTModem 2>/dev/null | head -40
echo
echo "=== /etc/init.d 下的相关服务 ==="
ls /etc/init.d/ | grep -iE 'modem|at|push|notif|cell'
echo
echo "=== 找 pps 相关（排除无关二进制）==="
grep -rl -iE 'pps' /etc/init.d/ /usr/lib/lua/ /www/cgi-bin/ /usr/share/ 2>/dev/null | head -20
echo
echo "=== 找含 pps 的文本文件 ==="
grep -rn -iE 'pps' /usr/lib/lua/luci/controller/ /usr/lib/lua/luci/view/ 2>/dev/null | head -20