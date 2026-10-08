#!/bin/sh
# 第三轮：用「明确的全局源地址」分别测两个出口，定位是链路问题还是源选择问题
W2V6=$(ip -6 addr show pppoe-wan | awk '/scope global/{print $2}' | cut -d/ -f1 | head -1)
LAN6=$(ip -6 addr show br-lan | awk '/scope global/{print $2}' | cut -d/ -f1 | head -1)
echo "pppoe-wan 全局地址 = $W2V6"
echo "br-lan     全局地址 = $LAN6"
echo

echo "===== A. 用 pppoe-wan 自己的全局地址作源 ====="
for t in 2400:3200::1 240e:f:a::6; do
  echo "--- src=$W2V6 -> $t ---"
  ping6 -c 3 -W 2 -I "$W2V6" "$t" 2>&1 | tail -3
done

echo
echo "===== B. 用 br-lan 全局地址作源（应走 wan 的 PD 路由）====="
for t in 2400:3200::1; do
  echo "--- src=$LAN6 -> $t ---"
  ping6 -c 3 -W 2 -I "$LAN6" "$t" 2>&1 | tail -3
done

echo
echo "===== C. 不指定源，看内核怎么选 ====="
ping6 -c 2 -W 2 2400:3200::1 2>&1 | tail -3

echo
echo "===== D. 停掉 wan6 之后再测（关键对比）====="
echo "--- 停之前先记录 br-lan 地址 ---"
ip -6 addr show br-lan | grep 'scope global'
ifdown wan6 2>&1
sleep 6
echo "--- 停掉 wan6 后 br-lan 地址 ---"
ip -6 addr show br-lan | grep 'scope global'
echo "--- 停掉 wan6 后的默认 v6 路由 ---"
ip -6 route show | grep default
echo "--- 现在测出口A v6 ---"
ping6 -c 3 -W 2 2400:3200::1 2>&1 | tail -3
echo "--- 现在测出口B v6 ---"
ping6 -c 3 -W 2 2409:8080::8 2>&1 | tail -3

echo
echo "===== E. 恢复 wan6 ====="
ifup wan6 2>&1
sleep 6
ip -6 addr show br-lan | grep 'scope global'
ping6 -c 2 -W 2 2400:3200::1 2>&1 | tail -3
