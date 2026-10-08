#!/bin/sh
# verify_rate5.sh — 同窗口严格对照：conntrack 按 mark 分出口 vs 接口计数
CONF=/etc/line-monitor/targets.conf
. "$CONF"

SPEC=$(printf '%s\n' $EXITS | awk -F'|' 'NF==0||$1==""{next}
  {m=$4;gsub(/,/," ",m);n=split(m,a," ");c=0;for(i=1;i<=n;i++)if(a[i]!="")c++
   if(c==0)next;s="";for(i=1;i<=n;i++)if(a[i]!="")s=s a[i] ",";sub(/,$/,"",s)
   printf "%s:%s:%s;",$1,$2,s}')

LAN=$(uci -q get network.lan.ipaddr)/$(uci -q get network.lan.netmask)
W=/tmp/v5.$$

snapct() {
    awk -v spec="$SPEC" -v lans="$LAN" '
function ip2int(s,  a,n){n=split(s,a,".");if(n!=4)return -1;return a[1]*16777216+a[2]*65536+a[3]*256+a[4]}
function in_lan(ip,  t,i,s){t=ip2int(ip);if(t<0)return 0;for(i=1;i<=lan_n;i++){s=2^(32-lan_bits[i]);if(int(t/s)==int(lan_net[i]/s))return 1}return 0}
BEGIN{
  lan_n=0;m=split(lans,p,/[\t ]+/)
  for(i=1;i<=m;i++){if(p[i]=="")continue;q=index(p[i],"/")
    if(q>0){a=substr(p[i],1,q-1);k=substr(p[i],q+1)}else{a=p[i];k=32}
    v=ip2int(a);if(v<0)continue;lan_n++;lan_net[lan_n]=v;lan_bits[lan_n]=k}
  n=split(spec,se,";")
  for(i=1;i<=n;i++){if(se[i]=="")continue;split(se[i],f,":");k=split(f[3],mm,",")
    for(j=1;j<=k;j++)if(mm[j]!="")want[mm[j]]=1}
}
{
  nb=0;b1=0;b2=0;mk="";src="";dst="";sp="";dp=""
  for(i=1;i<=NF;i++){p=index($i,"=");if(p<2)continue;f=substr($i,1,p-1);v=substr($i,p+1)
    if(f=="bytes"){nb++;if(nb==1)b1=v+0;else b2=v+0}
    else if(f=="mark")mk=v+0
    else if(f=="src"){if(src=="")src=v}
    else if(f=="dst"){if(dst=="")dst=v}
    else if(f=="sport"){if(sp=="")sp=v}
    else if(f=="dport"){if(dp=="")dp=v}}
  if(!(mk in want))next
  if(src==""||dst=="")next
  if(in_lan(dst)&&!in_lan(src)){u=b2;d=b1}else{u=b1;d=b2}
  printf "%s|%s|%s|%s|%s\t%.0f\t%.0f\n",mk,src,sp,dst,dp,u,d
}' /proc/net/nf_conntrack
}
snapdev() {
    awk '/^ *(eth0|br-lan|pppoe-wan|wan|BLUE4|rax0):/{n=$1;gsub(/:/,"",n);print n,$2,$10}' /proc/net/dev
}

snapct > $W.a
snapdev > $W.da
T0=$(date +%s)
sleep 20
snapct > $W.b
snapdev > $W.db
cat /tmp/lm_rate.json > $W.json
T1=$(date +%s)
DT=$((T1-T0))

echo "窗口 ${DT}s    conntrack 快照 $(( $(wc -l < $W.a) )) -> $(( $(wc -l < $W.b) )) 条"
echo
echo "=== conntrack 按 mark 分出口 ==="
awk -F'\t' -v dt="$DT" -v spec="$SPEC" '
NR==FNR{a[$1]=$2;au[$1]=$3;next}
{ if(!($1 in a)) next
  d2=$3-au[$1]; if(d2<0)d2=0
  d1=$2-a[$1];  if(d1<0)d1=0
  split($1,p,"|"); m=p[1]
  dn[m]+=d2; up[m]+=d1 }
END{
  n=split(spec,se,";")
  for(i=1;i<=n;i++){ if(se[i]=="")continue
    split(se[i],f,":"); ifc=f[1]; lbl=f[2]
    k=split(f[3],mm,","); tr=0; tu=0
    for(j=1;j<=k;j++){ m=mm[j]; tr+=dn[m]; tu+=up[m] }
    printf "  %-12s (%-6s)  down=%9.2f KB/s   up=%9.2f KB/s\n", ifc, lbl, tr/dt/1024, tu/dt/1024
    ifc_tr+=tr; ifc_tu+=tu
  }
  printf "  ---- 所有出口合计  down=%9.2f KB/s   up=%9.2f KB/s\n", ifc_tr/dt/1024, ifc_tu/dt/1024
  tr=0;tu=0; for(m in dn){tr+=dn[m];tu+=up[m]}
  printf "  ---- conntrack 总计 down=%9.2f KB/s   up=%9.2f KB/s\n", tr/dt/1024, tu/dt/1024
}' $W.a $W.b
echo
echo "=== 接口计数同窗口增量 ==="
awk -v dt="$DT" 'FNR==NR{rx[$1]=$2;tx[$1]=$3;next}
  {printf "  %-12s rx=%9.2f KB/s   tx=%9.2f KB/s\n",$1,($2-rx[$1])/dt/1024,($3-tx[$1])/dt/1024}' $W.da $W.db
echo
echo "=== 看板 JSON（2 秒窗口，不是 20 秒窗口，仅作参照） ==="
cat $W.json
rm -rf $W