#!/bin/sh
# diag_rate_diff.sh — 逐连接差分的匹配情况诊断
CONF=/etc/line-monitor/targets.conf
. "$CONF"
CT=/proc/net/nf_conntrack
MARKS=""
for e in $EXITS; do
    for m in $(echo "$e" | cut -d'|' -f4 | tr ',' ' '); do
        [ -z "$m" ] && continue
        MARKS="$MARKS$m "
    done
done

snap() {
    awk -v marks="$MARKS" '
    {
        nb=0;b1=0;b2=0;mk="";src="";dst="";sp="";dp=""
        for (i=1;i<=NF;i++) {
            p=index($i,"="); if(p<2) continue
            f=substr($i,1,p-1); v=substr($i,p+1)
            if      (f=="bytes"){nb++; if(nb==1)b1=v+0; else b2=v+0}
            else if (f=="mark") mk=v+0
            else if (f=="src")  {if(src=="")src=v}
            else if (f=="dst")  {if(dst=="")dst=v}
            else if (f=="sport"){if(sp=="")sp=v}
            else if (f=="dport"){if(dp=="")dp=v}
        }
        if (nb<2) next
        n=split(marks,mm," ")
        ok=0; for(i=1;i<=n;i++) if(mm[i]+0==mk) ok=1
        if(!ok) next
        if(src==""||dst=="") next
        printf "%s|%s|%s|%s|%s\t%.0f\t%.0f\n", mk,src,sp,dst,dp,b1,b2
    }' "$CT"
}

R=/tmp/drd
rm -rf $R; mkdir -p $R
snap > $R/a
T0=$(date +%s)
awk '/^ *(eth0|pppoe-wan2|br-lan|eth1):/ { n=$1; gsub(/:/,"",n); print n,$2,$10 }' /proc/net/dev > $R/dev_a
sleep 8
snap > $R/b
awk '/^ *(eth0|pppoe-wan2|br-lan|eth1):/ { n=$1; gsub(/:/,"",n); print n,$2,$10 }' /proc/net/dev > $R/dev_b
T1=$(date +%s)
DT=$((T1-T0))
echo "窗口 ${DT}s   快照行数 a=$(wc -l < $R/a) b=$(wc -l < $R/b)"
echo
echo "=== key 匹配情况 ==="
awk -F'\t' 'NR==FNR{k[$1]=1;na++;next} {nb++; if($1 in k) both++; else {new++} }
     END{ printf "旧 %d 条 / 新 %d 条 / 两边都有 %d 条 / 只在新快照 %d 条\n", na, nb, both, new }' $R/a $R/b
echo
echo "=== 哪些 key 只在新快照里（前 12，看是不是大流量连接换了 key） ==="
awk -F'\t' 'NR==FNR{k[$1]=1;next} !($1 in k) {print}' $R/a $R/b | sort -t'	' -k3 -rn | head -12
echo
echo "=== 哪些 key 只在旧快照里（前 12） ==="
awk -F'\t' 'NR==FNR{n[$1]=1;next} !($1 in n) {print}' $R/b $R/a | sort -t'	' -k3 -rn | head -12
echo
echo "=== 两边都有的 key 的字节增量，按 mark 聚合 ==="
awk -F'\t' 'NR==FNR{a[$1]=$2; c[$1]=$3; next}
     { if(!($1 in a)) next
       d2=$3-c[$1]; if(d2<0)d2=0
       split($1,p,"|"); m=p[1]
       dn[m]+=$3-c[$1]; up[m]+=$2-a[$1]
       if($3-c[$1]>0) act++
     }
     END{ for(m in up) printf "mark=%-6s down=%.2f MB/s  up=%.2f MB/s\n", m, dn[m]/(6*1048576), up[m]/(6*1048576)
          printf "有增量的连接数 = %d\n", act }' $R/a $R/b
echo
echo "=== 接口对照 ==="
awk -v dt="$DT" 'FNR==NR{rx[$1]=$2;tx[$1]=$3;next}
     { printf "%-12s rx=%9.2f KB/s  tx=%9.2f KB/s\n",$1,($2-rx[$1])/dt/1024,($3-tx[$1])/dt/1024 }' $R/dev_a $R/dev_b
echo
echo "=== conntrack 表容量与丢弃 ==="
cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null
cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null
grep -E "conntrack|evict|drop" /proc/net/stat/nf_conntrack 2>/dev/null
echo "insert_failed=$(cat /proc/sys/net/netfilter/nf_conntrack_attach 2>/dev/null)"