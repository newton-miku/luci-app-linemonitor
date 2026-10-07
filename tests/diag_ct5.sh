#!/bin/sh
# diag_ct5.sh — conntrack 完整五元组 key，按 mark 分 up/down；与接口计数对照
CT=/proc/net/nf_conntrack
snap() {
  awk 'BEGIN{OFS="\t"}
    {
      b1=0;b2=0;n=0;m="-";s1="";d1="";p1="";q1=""
      for(i=1;i<=NF;i++){
        split($i,kv,"=")
        if(kv[1]=="bytes"){ n++; if(n==1)b1=kv[2]+0; else b2=kv[2]+0 }
        if(kv[1]=="mark") m=kv[2]
        if(kv[1]=="src" && s1=="") s1=kv[2]
        if(kv[1]=="dst" && d1=="") d1=kv[2]
        if(kv[1]=="sport" && p1=="") p1=kv[2]
        if(kv[1]=="dport" && q1=="") q1=kv[2]
      }
      if(b1+b2>0) print m,s1,p1,d1,q1,b1,b2
    }' $CT
}
netsnap() {
  awk '/^ *(eth0|BLUE4|pppoe-wan2|eth1):/ { n=$1; gsub(/:/,"",n); print n,$2,$10 }' /proc/net/dev
}
snap > /tmp/c5a; netsnap > /tmp/n5a
T0=$(date +%s); sleep 12
snap > /tmp/c5b; netsnap > /tmp/n5b
DT=$(( $(date +%s) - T0 ))
echo "=== 窗口 ${DT}s ==="
echo
echo "=== conntrack 分 mark（完整五元组 key） ==="
awk -v dt="$DT" -F'\t' '
FNR==NR { key=$1"|"$2"|"$3"|"$4"|"$5; a1[key]=$6; a2[key]=$7; mk[key]=$1; next }
{ key=$1"|"$2"|"$3"|"$4"|"$5
  if(key in a1){
    d1=$6-a1[key]; d2=$7-a2[key]
    if(d1<0){ w1++; d1=0 }
    if(d2<0){ w2++; d2=0 }
    up[mk[key]]+=d1; dn[mk[key]]+=d2; tot++
    if(d1==0 && d2==0) frz++
  }
}
END { for(m in up) printf "mark=%-6s up=%9.2f KB/s  down=%10.2f KB/s  tot=%10.2f KB/s\n", m, up[m]/dt/1024, dn[m]/dt/1024, (up[m]+dn[m])/dt/1024
      printf "tracked=%d frozen=%d(%.0f%%) wrap_up=%d wrap_dn=%d\n", tot, frz, (tot>0?frz*100/tot:0), w1, w2 }
' /tmp/c5a /tmp/c5b | sort
echo
echo "=== conntrack 合计 ==="
awk -v dt="$DT" -F'\t' '
FNR==NR { key=$1"|"$2"|"$3"|"$4"|"$5; a1[key]=$6; a2[key]=$7; next }
{ key=$1"|"$2"|"$3"|"$4"|"$5
  if(key in a1){ d1=$6-a1[key]; d2=$7-a2[key]; if(d1<0)d1=0; if(d2<0)d2=0; t+=d1+d2 } }
END { printf "total %10.2f KB/s\n", t/dt/1024 }
' /tmp/c5a /tmp/c5b
echo
echo "=== 接口计数对照 ==="
awk -v dt="$DT" '
FNR==NR { rx[$1]=$2; tx[$1]=$3; next }
{ printf "%-12s rx=%10.2f KB/s  tx=%10.2f KB/s\n", $1, ($2-rx[$1])/dt/1024, ($3-tx[$1])/dt/1024 }
' /tmp/n5a /tmp/n5b