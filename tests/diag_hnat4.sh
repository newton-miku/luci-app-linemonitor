#!/bin/sh
# diag_hnat4.sh — 按「出口 + 方向」聚合 HNAT 表，验证能否还原真实 ↓↑
TELV4=$(ip -4 addr show dev pppoe-wan2 2>/dev/null | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')
MOBV4=$(ip -4 addr show dev eth1 2>/dev/null | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')
TELP6=$(ip -6 addr show dev pppoe-wan2 2>/dev/null | awk '/inet6 /{sub(/\/.*/,"",$2); print $2; exit}' | tr -d ':' | cut -c1-8 | tr 'a-f' 'A-F')
MOBP6=$(ip -6 addr show dev eth1 2>/dev/null | awk '/inet6 /{sub(/\/.*/,"",$2); print $2; exit}' | tr -d ':' | cut -c1-8 | tr 'a-f' 'A-F')
echo "TELV4=[$TELV4] MOBV4=[$MOBV4] TELP6=[$TELP6] MOBP6=[$MOBP6]"

parse() {
awk -v T4="$TELV4" -v M4="$MOBV4" -v T6="$TELP6" -v M6="$MOBP6" '
{
  if (match($0,/ppe=[0-9]+/)) p=substr($0,RSTART+4,RLENGTH-4); else p="0"
  if (match($0,/index=[0-9]+/)) i=substr($0,RSTART+6,RLENGTH-6); else next
  b=0; if (match($0,/bytes=[0-9]+/)) b=substr($0,RSTART+6,RLENGTH-6)+0
  n=split($0,parts,"=>")
  ex="OTH"
  if (T4!="" && index($0,T4)>0) ex="TEL"
  else if (M4!="" && index($0,M4)>0) ex="MOB"
  else if (T6!="" && index($0,T6)>0) ex="TEL"
  else if (M6!="" && index($0,M6)>0) ex="MOB"
  dir="tx"
  if (n>=2 && ex!="OTH") {
    p1=parts[1]
    if ((T4!="" && index(p1,T4)>0) || (M4!="" && index(p1,M4)>0) || (T6!="" && index(p1,T6)>0) || (M6!="" && index(p1,M6)>0)) dir="rx"
  }
  printf "%s_%s %d %s %s\n", p, i, b, ex, dir
}
' /sys/kernel/debug/hnat/all_entry 2>/dev/null
}

A0=$(cat /sys/class/net/eth0/statistics/rx_bytes); A1=$(cat /sys/class/net/eth0/statistics/tx_bytes)
parse > /tmp/hn_a
sleep 6
parse > /tmp/hn_b
B0=$(cat /sys/class/net/eth0/statistics/rx_bytes); B1=$(cat /sys/class/net/eth0/statistics/tx_bytes)

awk '
NR==FNR { A[$1]=$2; next }
{
  k=$1; d=$2-A[k]; if (d<0) d=$2
  ex=$3; dir=$4
  S[ex"_"dir]+=d; C[ex"_"dir]++
  if (d>200000) printf "  BIG %-8s %-3s %10d  %s\n", ex, dir, d, k
  TOT+=d
}
END {
  print "=== 6 秒增量（按出口+方向） ==="
  split("TEL MOB OTH",ks," ")
  for (j=1;j<=3;j++) { e=ks[j]
    printf "%-4s  rx=%10d  tx=%10d  (rx %d 条 / tx %d 条)\n", e, S[e"_rx"], S[e"_tx"], C[e"_rx"], C[e"_tx"]
  }
  printf "TOTAL = %d B / 6s = %.2f MB/s\n", TOT, TOT/6/1048576
}
' /tmp/hn_a /tmp/hn_b
echo "--- netdev 对照（6 秒） ---"
echo "eth0 rx=$((B0-A0)) tx=$((B1-A1))"
for f in pppoe-wan2 eth1 BLUE4 br-lan; do
  echo "$f rx=$(cat /sys/class/net/$f/statistics/rx_bytes) tx=$(cat /sys/class/net/$f/statistics/tx_bytes)"
done
