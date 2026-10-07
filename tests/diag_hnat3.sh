#!/bin/sh
# diag_hnat3.sh — 验证能否用 HNAT 表聚合出「分出口」真实速率
TELV4=$(ip -4 addr show dev pppoe-wan2 2>/dev/null | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')
MOBV4=$(ip -4 addr show dev eth1 2>/dev/null | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')
TELP6=$(ip -6 addr show dev pppoe-wan2 2>/dev/null | awk '/inet6 /{sub(/\/.*/,"",$2); print $2; exit}' | tr -d ':' | cut -c1-8 | tr 'a-f' 'A-F')
MOBP6=$(ip -6 addr show dev eth1 2>/dev/null | awk '/inet6 /{sub(/\/.*/,"",$2); print $2; exit}' | tr -d ':' | cut -c1-8 | tr 'a-f' 'A-F')
echo "TELV4=[$TELV4] MOBV4=[$MOBV4] TELP6=[$TELP6] MOBP6=[$MOBP6]"
echo "--- /proc/net 候选 ---"
ls /proc/net/ | tr '\n' ' '
echo
echo "--- all_entry 行数 ---"
wc -l < /sys/kernel/debug/hnat/all_entry
echo "--- netdev A ---"
for f in eth0 pppoe-wan2 eth1 BLUE4 br-lan; do
  echo "$f $(cat /sys/class/net/$f/statistics/rx_bytes) $(cat /sys/class/net/$f/statistics/tx_bytes)"
done
cat /sys/kernel/debug/hnat/all_entry > /tmp/hnat_a 2>/dev/null
sleep 6
cat /sys/kernel/debug/hnat/all_entry > /tmp/hnat_b 2>/dev/null
echo "--- netdev B ---"
for f in eth0 pppoe-wan2 eth1 BLUE4 br-lan; do
  echo "$f $(cat /sys/class/net/$f/statistics/rx_bytes) $(cat /sys/class/net/$f/statistics/tx_bytes)"
done
echo "--- HNAT 分出口 6 秒增量 ---"
awk -v T4="$TELV4" -v M4="$MOBV4" -v T6="$TELP6" -v M6="$MOBP6" '
NR==FNR {
  if (match($0,/index=[0-9]+/)) { i=substr($0,RSTART+6,RLENGTH-6) } else next
  b=0; if (match($0,/bytes=[0-9]+/)) b=substr($0,RSTART+6,RLENGTH-6)+0
  A[i]=b; next
}
{
  if (match($0,/index=[0-9]+/)) { i=substr($0,RSTART+6,RLENGTH-6) } else next
  b=0; if (match($0,/bytes=[0-9]+/)) b=substr($0,RSTART+6,RLENGTH-6)+0
  d=b-A[i]; if (d<0) d=b
  st="?"; if (match($0,/state=[A-Z]+/)) st=substr($0,RSTART+6,RLENGTH-6)
  e="OTH"
  if (T4!="" && index($0,T4)>0) e="TEL"
  else if (M4!="" && index($0,M4)>0) e="MOB"
  else if (T6!="" && index($0,T6)>0) e="TEL"
  else if (M6!="" && index($0,M6)>0) e="MOB"
  tot[e]+=d; cnt[e]++
  tot2[e"_"st]+=d; cnt2[e"_"st]++
}
END {
  for (k in tot) printf "%-4s total %10d B  (%d entries)\n", k, tot[k], cnt[k]
  print "-- by state --"
  for (k in tot2) printf "%-12s %10d B  (%d)\n", k, tot2[k], cnt2[k]
}
' /tmp/hnat_a /tmp/hnat_b
