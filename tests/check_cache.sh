#!/bin/sh
echo "=== after regen: linemon hits per cache ==="
for f in /tmp/luci-indexcache.*; do
  n=$(grep -o 'linemon' "$f" 2>/dev/null | wc -l)
  echo "$f -> hits=$n"
done
echo
echo "=== services entries in .lua cache ==="
grep -o 'admin/services/[a-z0-9-]*' /tmp/luci-indexcache.*.lua 2>/dev/null | sed 's/.*admin/services/&/' | sort -u | head -40
echo
echo "=== does .lua cache mention linemon path? ==="
grep -c 'linemon' /tmp/luci-indexcache.*.lua 2>/dev/null
echo
echo "=== head of .lua cache (structure) ==="
head -c 400 /tmp/luci-indexcache.*.lua
