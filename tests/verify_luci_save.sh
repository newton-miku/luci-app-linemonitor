echo "=== uci 里的值 ==="
uci show modem | grep -E 'feishu|wechat'
echo
echo "=== conf 文件 ==="
ls -l /usr/bin/smstrun-feishu.conf /usr/bin/smstrun.conf 2>&1
echo "--- feishu ---"; cat /usr/bin/smstrun-feishu.conf 2>/dev/null; echo
echo "--- pps ---"; cat /usr/bin/smstrun.conf 2>/dev/null; echo
echo
echo "=== 进程 ==="
ps w | grep '[s]mstrun.py' || echo "(没有进程)"
echo
echo "=== 日志 ==="
cat /tmp/smstrun.log 2>/dev/null
echo
echo "=== websocket 进程 ==="
ps w | grep '[w]ebsocket_server.py' || echo "(没有 websocket 进程)"