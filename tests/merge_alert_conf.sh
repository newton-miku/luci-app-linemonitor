#!/bin/sh
# install.sh 有意不覆盖已有 targets.conf，所以新配置项要手工合并进来
cp /etc/line-monitor/targets.conf "/tmp/targets.conf.bak.$(date +%s)"

echo "=== 改前 ==="
grep -n '^ALERT_' /etc/line-monitor/targets.conf

HAS_LOSS=$(grep -c '^ALERT_LOSS_PCT=' /etc/line-monitor/targets.conf)

awk -v hasloss="$HAS_LOSS" '
/^ALERT_MAX_MS=/ {
    print "ALERT_MAX_MS=1000"
    if (hasloss == 0) print "ALERT_LOSS_PCT=10"
    next
}
/^ALERT_COOLDOWN=/ { print "ALERT_COOLDOWN=0"; next }
{ print }
' /etc/line-monitor/targets.conf > /tmp/tc.new

mv /tmp/tc.new /etc/line-monitor/targets.conf

echo
echo "=== 改后 ==="
grep -n '^ALERT_' /etc/line-monitor/targets.conf

echo
echo "=== 新版 lm_alert.sh 是否含分级逻辑 ==="
grep -c 'ALERT_LOSS_PCT' /usr/bin/lm_alert.sh
grep -n 'level=loss\|level=down' /usr/bin/lm_alert.sh | head -6

echo
echo "=== hotplug 脚本在位 ==="
ls -l /etc/hotplug.d/iface/99-lm-v6-rule

echo
echo "=== v6 规则在位 ==="
ip -6 rule show | head -4

echo
echo "=== 采集一次，看电信 v6 是否恢复 ==="
sh /usr/bin/line_monitor.sh >/dev/null 2>&1
tail -n 1 /www/lm/history.log | tr ' ' '\n' | grep -E '^v6-' | sort

echo
echo "=== 告警状态（新版 --status 会显示 ok/down/loss）==="
/usr/bin/lm_alert.sh --status 2>&1 | head -6
/usr/bin/lm_alert.sh --status 2>&1 | tail -3
