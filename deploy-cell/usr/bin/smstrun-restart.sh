#!/bin/sh
# 重启内置蜂窝的短信转发进程。
# 改完 /usr/bin/smstrun-feishu.conf 或 /usr/bin/smstrun-title.conf 后跑一次。
#
# 注：这台固件没有 pkill，所以用 ps + kill。
for p in $(ps w | grep '[s]mstrun.py' | awk '{print $1}'); do kill "$p" 2>/dev/null; done
sleep 1
rm -f /tmp/smstrun.lock
nohup python3 /usr/bin/smstrun.py >/tmp/smstrun.log 2>&1 &
sleep 2
if ps w 2>/dev/null | grep -q '[s]mstrun.py'; then
    echo "转发进程已重启："
    ps w | grep '[s]mstrun.py'
else
    echo "转发进程没起来，看 /tmp/smstrun.log"
    tail -n 20 /tmp/smstrun.log 2>/dev/null
fi
