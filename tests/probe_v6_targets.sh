#!/bin/sh
# 找一组真的能 ping 通的 IPv6 目标（当前 2402:4e00:: 和 2409:8080::8 都不回包）
E1=$(ip -6 addr show dev eth1 scope global | awk '/inet6 /{sub(/\/.*/,"",$2); if ($2 !~ /^f[cd]/) { print $2; exit }}')
P6=$(ip -6 addr show dev pppoe-wan2 scope global | awk '/inet6 /{sub(/\/.*/,"",$2); if ($2 !~ /^f[cd]/) { print $2; exit }}')

CANDIDATES="
2400:3200::1|阿里DNS-v6
2400:3200:baba::1|阿里DNS-v6备
2402:4e00:1::|腾讯-v6候选1
2402:4e00:1000::|腾讯-v6候选2
2409:8000::|移动-v6候选1
2409:8080:1::1|移动-v6候选2
240e:4c:800::|电信-v6候选1
240e:5a::|电信-v6候选2
240c::6666|下一代DNS-v6
2620:0:ccc::2|OpenDNS-v6
2001:4860:4860::8888|Google-v6
"

printf '%-28s %-18s %-18s\n' "目标" "eth1(移动)" "pppoe-wan2(电信)"
for c in $CANDIDATES; do
    ip=${c%%|*}; nm=${c#*|}
    r1=$(ping6 -I "$E1"  -c 2 -W 2 "$ip" 2>/dev/null | awk '/round-trip/{split($0,a,"/"); print a[4]"ms"} /packet loss/{for(i=1;i<=NF;i++) if(index($i,"%")){print $i; exit}}' | tr '\n' ' ')
    r2=$(ping6 -I "$P6" -c 2 -W 2 "$ip" 2>/dev/null | awk '/round-trip/{split($0,a,"/"); print a[4]"ms"} /packet loss/{for(i=1;i<=NF;i++) if(index($i,"%")){print $i; exit}}' | tr '\n' ' ')
    printf '%-28s %-18s %-18s\n' "$nm $ip" "${r1:-无响应}" "${r2:-无响应}"
done
