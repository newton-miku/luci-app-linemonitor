echo "=== uci 值 ==="
uci show modem | grep -E 'feishu_webhook|wechat_webhook'
echo
echo "=== conf 时间戳（应为刚刚）==="
ls -l /usr/bin/smstrun-feishu.conf
date
echo "--- 内容 ---"
cat /usr/bin/smstrun-feishu.conf; echo
echo
echo "=== 进程（应只有 1 个）==="
ps w | grep '[s]mstrun.py'
echo
echo "=== hosts ==="
grep 'smstrun-feishu' /etc/hosts || echo "(无)"
echo
echo "=== 日志 ==="
cat /tmp/smstrun.log 2>/dev/null