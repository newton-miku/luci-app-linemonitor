#!/bin/sh
# diag_rate_dir.sh — 判定 /proc/net/dev 里 pppoe-wan / br-lan 的 rx/tx 方向是否可信
# 做法：路由器本机做一次明确方向的「下载」（从外网收），看哪个字段在涨
snap() {
    awk '/^ *(pppoe-wan|wan|br-lan|eth0):/ {
        name=$1; gsub(/:/,"",name);
        printf "%-12s rx=%-14s tx=%-14s\n", name, $2, $10
    }' /proc/net/dev
}
echo "=== BEFORE ==="
snap
echo
echo "=== 路由器本机下载 8 秒（明确是「收」） ==="
curl -s -o /dev/null --max-time 8 -w 'size=%{size_download} speed=%{speed_download}\n' \
    'http://mirrors.aliyun.com/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso'
echo
echo "=== AFTER ==="
snap
echo
echo "=== 顺带：tc / offload 状态 ==="
ls /sys/class/net/pppoe-wan/statistics/ 2>/dev/null | head -5
for i in rx_bytes tx_bytes; do
    echo -n "pppoe-wan $i = "
    cat /sys/class/net/pppoe-wan/statistics/$i 2>/dev/null || echo "(无)"
done
for i in rx_bytes tx_bytes; do
    echo -n "br-lan $i = "
    cat /sys/class/net/br-lan/statistics/$i 2>/dev/null || echo "(无)"
done
