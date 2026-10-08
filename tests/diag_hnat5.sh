#!/bin/sh
# diag_hnat5.sh — 打印 6 秒内增量最大的 HNAT entry 的完整 tuple，弄清 OTH 桶是什么
snap() { cat /sys/kernel/debug/hnat/all_entry 2>/dev/null; }
snap > /tmp/hn_a
sleep 6
snap > /tmp/hn_b
awk '
NR==FNR {
  k=""; if (match($0,/ppe=[0-9]+/)) k=substr($0,RSTART+4,RLENGTH-4)
  if (match($0,/index=[0-9]+/)) k=k"_"substr($0,RSTART+6,RLENGTH-6); else next
  b=0; if (match($0,/bytes=[0-9]+/)) b=substr($0,RSTART+6,RLENGTH-6)+0
  A[k]=b; next
}
{
  k=""; if (match($0,/ppe=[0-9]+/)) k=substr($0,RSTART+4,RLENGTH-4)
  if (match($0,/index=[0-9]+/)) k=k"_"substr($0,RSTART+6,RLENGTH-6); else next
  b=0; if (match($0,/bytes=[0-9]+/)) b=substr($0,RSTART+6,RLENGTH-6)+0
  d=b-A[k]; if (d<0) d=b
  if (d<300000) next
  st=""; if (match($0,/state=[A-Z]+/)) st=substr($0,RSTART+6,RLENGTH-6)
  ty=""; if (match($0,/type=[A-Z0-9_]+/)) ty=substr($0,RSTART+5,RLENGTH-5)
  t=""
  if (match($0,/type=[A-Z0-9_]+\|/)) { r=substr($0,RSTART+RLENGTH); sub(/\|.*/,"",r); t=r }
  printf "%12d %-7s %-16s %s\n", d, st, ty, t
}
' /tmp/hn_a /tmp/hn_b | sort -rn | head -22
echo "--- 全部 entry 的 type 分布 ---"
awk '{ if (match($0,/type=[A-Z0-9_]+/)) print substr($0,RSTART+5,RLENGTH-5) }' /tmp/hn_b | sort | uniq -c | sort -rn
echo "--- 含 203.0.113.10 的行数 ---"
grep -c '203.0.113.10' /tmp/hn_b
echo "--- 含 203.0.113.115 的行数 ---"
grep -c '203.0.113.115' /tmp/hn_b
echo "--- 含 192.168.66 的行数 ---"
grep -c '192.168.66' /tmp/hn_b
echo "--- 含 240e / 240E 的行数 ---"
grep -ci '240e' /tmp/hn_b
echo "--- 含 2409 的行数 ---"
grep -c '2409' /tmp/hn_b
