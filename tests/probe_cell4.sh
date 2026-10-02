echo "########## modem.lua 里所有 pps 上下文 ##########"
grep -n -iE 'pps' /usr/lib/lua/luci/model/cbi/modem.lua
echo
echo "########## modem5700-AK68.lua 里所有 pps 上下文 ##########"
grep -n -iE 'pps' /usr/lib/lua/luci/model/cbi/modem5700-AK68.lua
echo
echo "########## controller/modem-AK68.lua 的 ppsToken 处理段 ##########"
sed -n '55,95p' /usr/lib/lua/luci/controller/modem-AK68.lua
echo
echo "########## /usr/share/modem/rsmsc.sh ##########"
cat /usr/share/modem/rsmsc.sh
echo
echo "########## /usr/share/modem/smsc.sh ##########"
cat /usr/share/modem/smsc.sh