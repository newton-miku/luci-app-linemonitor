#!/bin/sh
# br_sample.sh — 每秒打印一次接口计数，供 Windows 侧做传输时对拍
i=1
while [ $i -le 15 ]; do
    awk -v t="$i" '/^ *(br-lan|eth0|wan|pppoe-wan):/ {
        name=$1; gsub(/:/,"",name);
        printf "t=%02d %-12s rx=%-14s tx=%-14s\n", t, name, $2, $10
    }' /proc/net/dev
    i=$((i + 1))
    sleep 1
done
