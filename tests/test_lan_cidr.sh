#!/bin/sh
# test_lan_cidr.sh — 验证 tcp_stream.sh 的内网网段匹配
#
# 重点是「掩码不一定是 /24」：老的实现是字符串前缀匹配（case "$src" in "$LAN_PREFIX"*)），
# 只能表达「以 192.168.66. 开头」，换成 /16 或 /25 就错了。
# 现在按位比较，本脚本用几个能区分对错的样本卡住它。

set -u
SRC_DIR=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 造一份 conntrack 样本。字段位置跟真机一致：
# $1=ipv4 $2=2 $3=tcp $4=6 $5=timeout $6=STATE $7=src= $8=dst= $9=sport= $10=dport= ...
# 两个方向上写 mark 的位置不同没关系，脚本是从 $11 往后扫的。
cat > "$TMP/ct" <<'EOF'
ipv4 2 tcp 6 431997 ESTABLISHED src=192.168.66.21 dst=101.226.10.20 sport=51234 dport=443 src=101.226.10.20 dst=100.81.9.22 sport=443 dport=51234 [ASSURED] mark=768 use=1
ipv4 2 tcp 6 431998 ESTABLISHED src=192.168.66.130 dst=1.2.4.8 sport=51235 dport=80 src=1.2.4.8 dst=100.81.9.22 sport=80 dport=51235 mark=768 use=1
ipv4 2 tcp 6 431999 ESTABLISHED src=192.168.67.5 dst=114.114.114.114 sport=51236 dport=53 src=114.114.114.114 dst=100.81.9.22 sport=53 dport=51236 mark=256 use=1
ipv4 2 tcp 6 432000 ESTABLISHED src=10.1.2.3 dst=8.8.8.8 sport=51237 dport=53 src=8.8.8.8 dst=100.81.9.22 sport=53 dport=51237 mark=256 use=1
ipv4 2 tcp 6 432001 ESTABLISHED src=192.168.66.24 dst=223.5.5.5 sport=51238 dport=53 src=223.5.5.5 dst=100.81.9.22 sport=53 dport=51238 mark=256 use=1
ipv4 2 tcp 6 432002 ESTABLISHED src=172.16.9.9 dst=9.9.9.9 sport=51239 dport=53 src=9.9.9.9 dst=100.81.9.22 sport=53 dport=51239 mark=256 use=1
EOF

# 复刻 tcp_stream.sh：换掉配置来源、conntrack 路径、输出路径、ipmap
make_run() {
    sed -e 's#^\. /etc/line-monitor/targets.conf#EXITS="eth1\|移动\|auto\|256\|both"#' \
        -e "s#/proc/net/nf_conntrack#$TMP/ct#" \
        -e "s#^IPMAP=.*#IPMAP=$TMP/no_ipmap#" \
        -e "s#^OUT=.*#OUT=$TMP/out.json#" \
        -e '/lm_config_json/d' \
        "$SRC_DIR/deploy/usr/bin/tcp_stream.sh" > "$TMP/run.sh"
    chmod +x "$TMP/run.sh"
}

clients() {
    # 从输出的 JSON 里抽出所有 client 值，排序去重后一行一个
    sed 's/},{/}\n{/g' "$TMP/out.json" | grep -o '"client":"[^"]*"' | sed 's/.*:"//; s/"//' | sort -u
}

check() {
    # $1 = 描述  $2 = LAN_NETS  $3 = 期望出现的 client（空格分隔）
    LAN_NETS="$2" sh -c "LAN_NETS='$2' $TMP/run.sh" >/dev/null 2>&1
    got=$(clients | tr '\n' ' ' | sed 's/ *$//')
    want=$(printf '%s' "$3" | sed 's/^ *//; s/ *$//')
    if [ "$got" = "$want" ]; then
        printf 'OK   %-34s %s\n' "$1" "[$got]"
    else
        printf 'FAIL %-34s 期望 [%s] 实得 [%s]\n' "$1" "$want" "$got"
        return 1
    fi
}

make_run
FAILED=0

# /24：21 和 24 在内、130 也在内（/24 覆盖全段），67.5 和 10/172 段在外
check "192.168.66.0/24" "192.168.66.0/24" \
      "192.168.66.130 192.168.66.21 192.168.66.24"

# /25：21 在内（<128），130 在外（>=128）—— 前缀匹配在这里必然判错
check "192.168.66.0/25" "192.168.66.0/25" \
      "192.168.66.21 192.168.66.24"

# /16：192.168.67.5 也进来 —— 旧的前缀匹配漏掉它
check "192.168.0.0/16" "192.168.0.0/16" \
      "192.168.66.130 192.168.66.21 192.168.66.24 192.168.67.5"

# 点分掩码要跟位数等价
check "255.255.255.0 写法" "192.168.66.0/255.255.255.0" \
      "192.168.66.130 192.168.66.21 192.168.66.24"

# 多网段
check "多网段 /24 + /8" "192.168.66.0/24 10.0.0.0/8" \
      "10.1.2.3 192.168.66.130 192.168.66.21 192.168.66.24"

# /32 只命中单个地址
check "/32 单机" "192.168.66.21/32" "192.168.66.21"

# /8 全覆盖
check "10.0.0.0/8" "10.0.0.0/8" "10.1.2.3"

# 不带掩码按 /32 算
check "裸地址 192.168.66.21" "192.168.66.21" "192.168.66.21"

# 空配置：一个都不匹配（自动识别失败时的最坏情况，不该误判成全放行）
check "空网段" "" ""

echo "---"
if [ "$FAILED" -eq 0 ]; then echo "全部通过"; else echo "有失败项"; fi
exit $FAILED
