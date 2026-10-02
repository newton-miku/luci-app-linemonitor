rm -rf /tmp/lmc && mkdir -p /tmp/lmc
tar -xf /tmp/lmcell.tar -C /tmp/lmc
FEISHU_URL='https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_HOOK_ID' sh /tmp/lmc/deploy-cell/install.sh
echo
echo "########## patch 结果关键片段 ##########"
grep -n 'feishu_webhook\|inputstyle = "saveapply"\|formvalue(section) or self\|for p in \$(ps w\|smstrun-feishu.conf' /usr/lib/lua/luci/model/cbi/modem.lua
echo
echo "########## lua 语法 ##########"
lua -e 'local f,err=loadfile("/usr/lib/lua/luci/model/cbi/modem.lua"); if f then print("LUA_SYNTAX_OK") else print("LUA_SYNTAX_ERR: "..tostring(err)) end'
echo
echo "########## 进程（应该只剩 1 个）##########"
ps w | grep '[s]mstrun.py'