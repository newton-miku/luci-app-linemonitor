#!/bin/sh
# 验收：删掉 seen 里一条 4 段长短信的键，让它重新走一遍「攒段 -> 拼齐 -> 推飞书」全链路。
# 既能证明新装的四道过滤没把真短信误杀，也能证明飞书推送仍然活着。
KEY='106589666300@10/05/26_03:51:55'

echo "==> 该键当前是否在 seen 里"
grep -n "$KEY" /etc/smstrun-seen.conf || echo "(不在)"
echo

echo "==> 备份并删除该键"
cp /etc/smstrun-seen.conf /tmp/seen.before.trigger
awk -v k="$KEY" '$1 != k' /etc/smstrun-seen.conf > /tmp/s.new && mv /tmp/s.new /etc/smstrun-seen.conf
echo "剩余行数: $(wc -l < /etc/smstrun-seen.conf)"
echo

echo "==> 等 30 秒（约 3~4 轮采集）"
sleep 30

echo "--- 日志尾部 ---"
tail -n 12 /tmp/smstrun.log

echo
echo "--- 该键是否被重新写回 seen（写回说明真短信确实被采集到了） ---"
grep "$KEY" /etc/smstrun-seen.conf || echo "(未回写)"
