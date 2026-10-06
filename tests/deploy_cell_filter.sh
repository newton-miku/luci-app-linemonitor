#!/bin/sh
# 部署带垃圾过滤的 smstrun.sh/smstrun.py，并清掉 seen 里已经攒下的乱码键。
set -e

echo "==> 备份 seen"
cp /etc/smstrun-seen.conf /tmp/seen.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true

echo "==> 停转发进程"
for p in $(ps w | grep '[s]mstrun.py' | awk '{print $1}'); do kill "$p" 2>/dev/null || true; done
sleep 2
rm -f /tmp/smstrun.lock

echo "==> 清理 seen 里的垃圾键（发件人不是纯数字的一律删）"
before=$(wc -l < /etc/smstrun-seen.conf 2>/dev/null || echo 0)
awk '$1 ~ /^\+?[0-9]+@/' /etc/smstrun-seen.conf > /tmp/seen.new 2>/dev/null || : > /tmp/seen.new
mv /tmp/seen.new /etc/smstrun-seen.conf
after=$(wc -l < /etc/smstrun-seen.conf)
echo "    $before -> $after 行"

echo "==> 安装 deploy-cell"
rm -rf /tmp/cld
mkdir -p /tmp/cld
tar -xf /tmp/celldeploy.tar -C /tmp/cld
sh /tmp/cld/deploy-cell/install.sh

echo
echo "==> 等 40 秒收两轮，看日志"
sleep 40
echo "--- /tmp/smstrun.log 尾部 ---"
tail -n 20 /tmp/smstrun.log 2>/dev/null

echo
echo "--- 当前 seen 行数 ---"
wc -l < /etc/smstrun-seen.conf
