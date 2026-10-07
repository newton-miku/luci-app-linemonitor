#!/bin/sh
# diag_ct3.sh — 量化 conntrack 分出口字节速率 vs 接口计数
CT=/proc/net/nf_conntrack
snap() {
  awk 'BEGIN{OFS="\t"}
    {
      b1=0;b2=0;n=0;m="-";s1="";d1="";p1=""
      for(i=1;i<=NF;i++){
        split($i,kv,"=")
        if(kv[1]=="bytes"){ n++; if(n==1)b1=kv[2]+0; else b2=kv[2]+0 }
        if(kv[1]=="mark") m=kv[2]
        if(kv[1]=="src" && s1=="") s1=kv[2]
        if(kv[1]=="dst" && d1=="") d1=kv[2]
        if(kv[1]=="sport" && p1=="") p1=kv[2]
      }
      if(b1+b2>0) print m,s1,p1,d1,b1,b2
    }' $CT
}
netsnap() {
  awk '/^ *(eth0|BLUE4|pppoe-wan2|br-lan|eth1|lan2|eth3):/ {
    name=$1; gsub(/:/,"",name); print name, $2, $10
  }' /proc/net/dev
}
snap > /tmp/ct3_a
netsnap > /tmp/net3_a
T0=$(date +%s)
sleep 12
snap > /tmp/ct3_b
netsnap > /tmp/net3_b
T1=$(date +%s)
DT=$((T1 - T0))
echo "=== 窗口 ${DT}s ==="
echo
echo "=== conntrack 分 mark 字节增量 ==="
awk -v dt="$DT" -F'\t' '
FNR==NR { key=$1"|"$2"|"$3"|"$4; a[key]=$5+$6; mk[key]=$1; next }
{ key=$1"|"$2"|"$3"|"$4
  if(key in a){ d=($5+$6)-a[key]; if(d<0){ neg[mk[key]]+=d; d=0 } sum[mk[key]]+=d; tot++; if(d==0) frozen++ }
  else { newc++ }
}
END { for(m in sum) printf "mark=%-6s %8.2f KB/s %7.3f MB/s%s\n", m, sum[m]/dt/1024, sum[m]/dt/1048576, (neg[m]!=0?" [回绕 "neg[m]"]":"")
      printf "tracked=%d frozen=%d (%.1f%%) new=%d\n", tot, frozen, (tot>0?frozen*100/tot:0), newc }
' /tmp/ct3_a /tmp/ct3_b
echo
echo "=== conntrack 合计 ==="
awk -v dt="$DT" -F'\t' '
FNR==NR { key=$1"|"$2"|"$3"|"$4; a[key]=$5+$6; next }
{ key=$1"|"$2"|"$3"|"$4; if(key in a) t+=($5+$6)-a[key] }
END { printf "total %8.2f KB/s  %7.3f MB/s\n", t/dt/1024, t/dt/1048576 }
' /tmp/ct3_a /tmp/ct3_b
echo
echo "=== 接口计数增量 ==="
awk -v dt="$DT" '
FNR==NR { rx[$1]=$2; tx[$1]=$3; next }
{ printf "%-12s rx=%10.2f KB/s  tx=%10.2f KB/s\n", $1, ($2-rx[$1])/dt/1024, ($3-tx[$1])/dt/1024 }
' /tmp/net3_a /tmp/net3_b
echo
echo "=== 饱和 bytes=2147483647 行数 ==="
grep -c 'bytes=2147483647' $CT
echo "=== conntrack 总行数 ==="
wc -l < $CT