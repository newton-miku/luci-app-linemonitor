#!/bin/sh
# diag_ct4.sh — conntrack 按 mark 分方向累加（b1=上传 b2=下载），验证能否替代接口计数
CT=/proc/net/nf_conntrack
snap() {
  awk 'BEGIN{OFS="\t"}
    {
      b1=0;b2=0;n=0;m="-";s1=""
      for(i=1;i<=NF;i++){
        split($i,kv,"=")
        if(kv[1]=="bytes"){ n++; if(n==1)b1=kv[2]+0; else b2=kv[2]+0 }
        if(kv[1]=="mark") m=kv[2]
        if(kv[1]=="src" && s1=="") s1=kv[2]
      }
      if(b1+b2>0) print m,s1,b1,b2
    }' $CT
}
netsnap() {
  awk '/^ *(eth0|BLUE4|pppoe-wan2|eth1):/ { name=$1; gsub(/:/,"",name); print name,$2,$10 }' /proc/net/dev
}
snap > /tmp/c4a; netsnap > /tmp/n4a
T0=$(date +%s); sleep 12
snap > /tmp/c4b; netsnap > /tmp/n4b
DT=$(( $(date +%s) - T0 ))
echo "=== 窗口 ${DT}s ==="
echo
echo "=== conntrack 分 mark：up(b1=发起方向/上传) down(b2=应答方向/下载) ==="
awk -v dt="$DT" -F'\t' '
FNR==NR { key=$1"|"$2; a[key]=$3; b[key]=$4; mk[key]=$1; next }
{ key=$1"|"$2
  if(key in a){
    d1=$3-a[key]; d2=$4-b[key]
    if(d1<0){ wrap1++; d1=0 }        # INT32_MAX 回绕
    if(d2<0){ wrap2++; d2=0 }
    up[mk[key]]+=d1; dn[mk[key]]+=d2
  }
}
END { for(m in up) printf "mark=%-6s up=%8.2f KB/s  down=%9.2f KB/s  total=%9.2f KB/s\n", m, up[m]/dt/1024, dn[m]/dt/1024, (up[m]+dn[m])/dt/1024
      printf "wrap(up)=%d wrap(down)=%d\n", wrap1, wrap2 }
' /tmp/c4a /tmp/c4b | sort
echo
echo "=== 接口计数对照 ==="
awk -v dt="$DT" -F'\t' '
FNR==NR { rx[$1]=$2; tx[$1]=$3; next }
{ printf "%-12s rx=%9.2f KB/s  tx=%9.2f KB/s\n", $1, ($2-rx[$1])/dt/1024, ($3-tx[$1])/dt/1024 }
' /tmp/n4a /tmp/n4b
echo
echo "=== EXITS 里配置的 mark ==="
grep '^EXITS=' /etc/line-monitor/targets.conf
echo
echo "=== mwan3 实际 mark 映射 ==="
grep -rn "mark" /etc/config/mwan3 2>/dev/null | head -20