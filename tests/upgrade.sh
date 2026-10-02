#!/bin/sh
# 用新版覆盖部署：备份 -> 停服务 -> 解包 -> 覆盖配置 -> install.sh -> 起服务
set -e
TS=$(date +%Y%m%d-%H%M%S)

echo "=== 1. 备份 ==="
mkdir -p "/root/lm-backup-$TS"
for f in /etc/line-monitor/targets.conf /usr/bin/line_monitor.sh /usr/bin/tcp_stream.sh \
         /usr/bin/line_daemon.sh /etc/init.d/linemon /www/lm/line.html; do
    [ -f "$f" ] && cp "$f" "/root/lm-backup-$TS/" 2>/dev/null
done
tar -czf "/root/lm-upgrade-$TS.tar.gz" -C "/root/lm-backup-$TS" . 2>/dev/null
echo "备份 -> /root/lm-upgrade-$TS.tar.gz"

echo "=== 2. 停服务 ==="
/etc/init.d/linemon stop 2>/dev/null || true
killall line_daemon.sh 2>/dev/null || true
sleep 1
killall -9 line_daemon.sh 2>/dev/null || true
rm -f /tmp/lm_monitor.lock
ps | grep -c "[l]ine_daemon" || true

echo "=== 3. 解包 ==="
rm -rf /tmp/lmd
mkdir -p /tmp/lmd
tar -xf /tmp/lmdeploy.tar -C /tmp/lmd
ls -l /tmp/lmd/deploy/

echo "=== 4. 覆盖配置（旧的先留一份）==="
[ -f /etc/line-monitor/targets.conf ] && cp /etc/line-monitor/targets.conf "/root/lm-backup-$TS/targets.conf.old"
cp /tmp/lmd/deploy/etc/line-monitor/targets.conf /etc/line-monitor/targets.conf

echo "=== 5. 安装 ==="
sh /tmp/lmd/deploy/install.sh

echo "=== 6. 起服务后的状态 ==="
sleep 3
/etc/init.d/linemon status 2>&1 | head -3
ls -l /usr/bin/line_monitor.sh /usr/bin/tcp_stream.sh /usr/bin/line_daemon.sh \
      /usr/bin/lm_config_json.sh /www/cgi-bin/lm-config /www/lm/config.html /www/lm/line.html
