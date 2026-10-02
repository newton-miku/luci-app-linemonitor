#!/bin/sh
echo "=== Argon 主题模板位置 ==="
ls /usr/lib/lua/luci/view/themes/ 2>/dev/null
find /usr/lib/lua/luci/view -name 'header.htm' 2>/dev/null

echo
echo "=== indexcache(.json) 里 linemon 的上下文 ==="
for f in /tmp/luci-indexcache.*.json; do
  echo "--- $f ---"
  grep -o '.\{80\}linemon.\{80\}' "$f" 2>/dev/null
done

echo
echo "=== indexcache(.json) 里 mosdns 的上下文（对照） ==="
for f in /tmp/luci-indexcache.*.json; do
  grep -o '.\{60\}mosdns.\{60\}' "$f" 2>/dev/null | head -4
done

echo
echo "=== admin/services 节点在缓存里的样子 ==="
for f in /tmp/luci-indexcache.*.json; do
  grep -o '.\{0,40\}admin/services.\{0,120\}' "$f" 2>/dev/null | head -6
done
