echo "=== uci 里的 wechat_webhook 与相关项 ==="
uci get modem.ndis.wechat_webhook 2>&1
echo "--- 全部 modem 配置里的通知项 ---"
uci show modem 2>/dev/null | grep -E 'notification|wechat|smsen|log_file|manage_ak68'
echo
echo "=== smstrun.py 全文（WTModem 那套）==="
cat /usr/bin/smstrun.py
echo
echo "=== smstrun.sh（非 AK68）==="
cat /usr/bin/smstrun.sh
echo
echo "=== 哪些进程在跑 smstrun ==="
ps w | grep -i smstrun | grep -v grep
echo
echo "=== 非 AK68 settings 视图在哪 ==="
ls -la /usr/lib/lua/luci/view/zmode/
echo
echo "=== zmode/settings.htm 里的 pps 相关 ==="
grep -n -iE 'pps|token|webhook|sms' /usr/lib/lua/luci/view/zmode/settings.htm 2>/dev/null | head -30