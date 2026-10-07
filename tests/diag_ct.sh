#!/bin/sh
# diag_ct.sh — 验证 conntrack 计数是否仍随 HNAT 卸载流量增长（若有，就是最干净的取数源）
echo "--- nf_conntrack 行数 ---"
wc -l < /proc/net/nf_conntrack 2>&1
echo "--- 前 2 行 ---"
head -2 /proc/net/nf_conntrack 2>&1
snapct() {
  awk '{
    b1=0;b2=0;n=0;m="-";s1="";d1="";p1="";p2=""
    for(i=1;i<=NF;i++){
      split($i,kv,"=")
      if(kv[1]=="bytes"){ n++; if(n==1)b1=kv[2]+0; else b2=kv[2]+0 }
      if(kv[1]=="mark") m=kv[2]
      if(kv[1]=="src" && s1=="") s1=kv[2]
      if(kv[1]=="dst" && d1=="") d1=kv[2]
      if(kv[1]=="sport" && p1=="") p1=kv[2]
      if(kv[1]=="dport" && p2=="") p2=kv[2]
    }
    if(b1+b2>500000) printf "%s|%s:%s->%s:%s|b1=%d|b2=%d\n", m,s1,p1,d1,p2,b1,b2
  }' /proc/net/nf_conntrack
}
snapct > /tmp/ct_a
sleep 5
snapct > /tmp/ct_b
echo "--- A（5 秒前，bytes>500KB 的连接） ---"
cat /tmp/ct_a
echo "--- B（现在） ---"
cat /tmp/ct_b
echo "--- mark 分布（全部连接） ---"
awk '{ for(i=1;i<=NF;i++) if($i ~ /^mark=/){ print substr($i,6); break } }' /proc/net/nf_conntrack | sort | uniq -c | sort -rn
