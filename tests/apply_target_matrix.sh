#!/bin/sh
# 把机器上已有的 /etc/line-monitor/targets.conf 从「目标分组」模型
# 迁到「显式目标清单」模型（出口第 6 字段 = 目标名，逗号分隔）。
#
# 为什么必须单独跑一次：install.sh 有意不覆盖已有的 targets.conf。
# 旧文件里第 6 字段写的是分组名（公网/内网），新代码按目标名匹配，
# 名字对不上就一条目标都不测 —— 迁移前请先跑这个。
#
# 只在已经跑过旧版的机器上需要跑，装新机器不用（deploy 里带的已经是新格式）。

set -e
F=/etc/line-monitor/targets.conf
BAK=/root/lm-targets.conf.$(date +%Y%m%d-%H%M%S).bak

[ -f "$F" ] || { echo "找不到 $F"; exit 1; }
cp "$F" "$BAK"

# 下面三行按当前拓扑写死（2026-10-04 的配置）。
# 目标列表改过就要自己核一遍：外网出口列公网目标，组网出口列对端。
PUB='阿里DNS,腾讯DNS,CNNIC,微信,淘宝,B站,抖音,QQ,阿里v6,移动v6,国际v6'
LAN='op-nj,cd-ubuntu22,ubunt-hb'

sed -i "s#^eth1|移动|auto|256|both|.*\$#eth1|移动|auto|256|both|$PUB#" "$F"
sed -i "s#^pppoe-wan2|电信||512,768|both|.*\$#pppoe-wan2|电信||512,768|both|$PUB#" "$F"
sed -i "s#^tailscale0|tailscale组网|||v4|.*\$#tailscale0|tailscale组网|||v4|$LAN#" "$F"

echo "备份：$BAK"
echo "---- 迁移后的 EXITS ----"
sed -n '/^EXITS=/,/^"$/p' "$F"
