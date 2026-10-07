#!/bin/sh
# diag_rate_dir2.sh — 让路由器本机做一次明确方向的「下载」，看 pppoe-wan2/eth1 哪个字段涨
echo "=== 外网 HTTP 可达性 ==="
curl -s -o /dev/null -w 'aliyun root : http=%{http_code} t=%{time_total}\n' --max-time 6 'http://mirrors.aliyun.com/'
curl -s -o /dev/null -w 'aliyun ls-lR: http=%{http_code} size=%{size_download}\n' --max-time 6 'http://mirrors.aliyun.com/ubuntu/ls-lR.gz'
echo
echo "=== 采样 10 秒（前 1 秒空闲，后 7 秒本机下载） ==="
(
    i=1
    while [ $i -le 10 ]; do
        awk -v t="$i" '/^ *(pppoe-wan2|eth1|br-lan):/ {
            name=$1; gsub(/:/,"",name);
            printf "t=%02d %-12s rx=%-14s tx=%-14s\n", t, name, $2, $10
        }' /proc/net/dev
        i=$((i + 1))
        sleep 1
    done
) > /tmp/_sample.out 2>&1 &
SPID=$!
sleep 1
curl -s -o /dev/null --max-time 7 -w 'download: size=%{size_download} speed=%{speed_download}\n' 'http://mirrors.aliyun.com/ubuntu/ls-lR.gz'
wait $SPID
echo "--- 采样结果 ---"
cat /tmp/_sample.out
