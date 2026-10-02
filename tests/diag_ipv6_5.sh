#!/bin/sh
# 第四轮：确认禁用 wan6 后哪些 v6 目标真的可达，为改配置提供依据
echo "===== 当前状态（wan6 已恢复）====="
ip -6 addr show br-lan | grep 'scope global'
ping6 -c 2 -W 2 2400:3200::1 2>&1 | tail -2
echo

echo "===== 停掉 wan6，逐个测候选目标 ====="
ifdown wan6 2>&1
sleep 6
echo "br-lan:"; ip -6 addr show br-lan | grep 'scope global'
echo "默认路由:"; ip -6 route show | grep default
echo
for t in 2400:3200::1 240e:f:a::6 2402:4e00:: 240c::6666 2409:8080::8 2001:4860:4860::8888; do
  echo "--- $t ---"
  ping6 -c 2 -W 2 "$t" 2>&1 | tail -2
done

echo
echo "===== 恢复 wan6 ====="
ifup wan6 2>&1
sleep 5
echo "br-lan:"; ip -6 addr show br-lan | grep 'scope global'
ping6 -c 2 -W 2 2400:3200::1 2>&1 | tail -2
