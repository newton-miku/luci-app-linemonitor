#!/bin/sh
# diag_hnat2.sh — 找 HNAT 卸载后仍能看到真实流量的数据源
echo "=== hnat_stats ==="
cat /sys/kernel/debug/hnat/hnat_stats 2>/dev/null
echo
echo "=== hnat_entry (head 20) ==="
head -20 /sys/kernel/debug/hnat/hnat_entry 2>/dev/null
echo
echo "=== all_entry (head 30) ==="
head -30 /sys/kernel/debug/hnat/all_entry 2>/dev/null
echo
echo "=== external_interface ==="
cat /sys/kernel/debug/hnat/external_interface 2>/dev/null
echo
echo "=== whnat_interface ==="
cat /sys/kernel/debug/hnat/whnat_interface 2>/dev/null
echo
echo "=== hnat_setting ==="
cat /sys/kernel/debug/hnat/hnat_setting 2>/dev/null
echo
echo "=== hook_toggle ==="
cat /sys/kernel/debug/hnat/hook_toggle 2>/dev/null
echo
echo "=== cpu_reason ==="
cat /sys/kernel/debug/hnat/cpu_reason 2>/dev/null | head -20
echo
echo "=== /proc/mtketh/esw_cnt ==="
cat /proc/mtketh/esw_cnt 2>/dev/null
echo
echo "=== /proc/mtketh/rx_ring (head 20) ==="
head -20 /proc/mtketh/rx_ring 2>/dev/null
echo
echo "=== /proc/mtketh/hwtx_ring (head 20) ==="
head -20 /proc/mtketh/hwtx_ring 2>/dev/null
