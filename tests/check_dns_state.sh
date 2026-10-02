#!/bin/sh
# 检查路由器当前 DNS 状态与飞书转发进程。
echo '--- resolv.conf ---'
cat /etc/resolv.conf
echo '--- getaddrinfo ---'
python3 - <<'PY'
import socket
try:
    print("OK:", socket.getaddrinfo('open.feishu.cn', 443, socket.AF_INET)[0][4])
except Exception as e:
    print("FAIL:", e)
PY
echo '--- /etc/hosts (smstrun) ---'
grep smstrun /etc/hosts || echo '(无条目)'
echo '--- smstrun.log ---'
tail -5 /tmp/smstrun.log 2>/dev/null || echo '(空)'
echo '--- proc ---'
ps w | grep '[s]mstrun.py' || echo '(未运行)'
