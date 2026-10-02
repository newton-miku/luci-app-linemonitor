echo "########## zmode/webui.htm ##########"
cat /usr/lib/lua/luci/view/zmode/webui.htm
echo
echo "########## modem.lua 的 WEBUI tab 段落（490-540）##########"
sed -n '490,540p' /usr/lib/lua/luci/model/cbi/modem.lua
echo
echo "########## 谁引用了 smstrun ##########"
grep -rn 'smstrun' /usr/lib/lua/luci/ /etc/init.d/ /etc/rc.local /usr/share/modem/ 2>/dev/null | head -20
echo
echo "########## rc.local 内容 ##########"
cat /etc/rc.local 2>/dev/null