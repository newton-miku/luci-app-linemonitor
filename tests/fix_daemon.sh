#!/bin/sh
# 清掉重复的 line_daemon.sh / line_monitor.sh，再由 procd 重新拉起唯一一份。
for p in $(ps w | grep '[l]ine_daemon.sh' | awk '{print $1}'); do kill "$p" 2>/dev/null; done
for p in $(ps w | grep '[l]ine_monitor.sh' | awk '{print $1}'); do kill "$p" 2>/dev/null; done
sleep 1
rm -f /tmp/lm_monitor.lock
/etc/init.d/linemon restart >/dev/null 2>&1
sleep 5
echo "--- after ---"
ps w | grep -E '[l]ine_'
echo "--- count ---"
ps w | grep -c '[l]ine_daemon.sh'
echo "--- svc ---"
/etc/init.d/linemon status 2>&1 | head -2
echo "--- log tail ts ---"
tail -3 /www/lm/history.log | cut -d' ' -f1
