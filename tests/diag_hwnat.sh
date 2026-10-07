#!/bin/sh
# diag_hwnat.sh — 找出哪个接口能看到真实流量（硬件加速会绕过软件接口统计）
echo "=== /proc/net/dev 全量 ==="
cat /proc/net/dev
echo
echo "=== /sys/class/net/*/statistics 5 轮（每 2 秒） ==="
i=1
while [ $i -le 5 ]; do
    echo "--- round $i ---"
    for f in BLUE4 eth0 eth1 eth2 pppoe-wan2 br-lan lan1 lan2 lan3 ra0 rax0; do
        rx=$(cat /sys/class/net/$f/statistics/rx_bytes 2>/dev/null) || continue
        tx=$(cat /sys/class/net/$f/statistics/tx_bytes 2>/dev/null)
        echo "$f rx=$rx tx=$tx"
    done
    i=$((i + 1))
    sleep 2
done
echo
echo "=== 硬件加速痕迹 ==="
ls /sys/kernel/debug/ 2>/dev/null | head -20
echo "--- hnat ---"
ls /sys/kernel/debug/hnat/ 2>/dev/null
cat /sys/kernel/debug/hnat/hook_tbl 2>/dev/null | head -10
echo "--- mtketh ---"
ls /proc/mtketh 2>/dev/null
cat /proc/mtketh/hwnat 2>/dev/null | head -20
echo "--- fastpath / shortcut ---"
ls /proc/sys/net/ 2>/dev/null | grep -iE 'fast|shortcut|hnat'
cat /proc/sys/net/hook_shortcut_enable 2>/dev/null
echo "--- lsmod 加速模块 ---"
lsmod 2>/dev/null | grep -iE 'hnat|fastpath|shortcut|mtk|ppe|ra_' | head -20
