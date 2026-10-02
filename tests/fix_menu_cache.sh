#!/bin/sh
echo "=== before: grep linemon in each cache ==="
for f in /tmp/luci-indexcache.*; do
  n=$(grep -o 'linemon' "$f" 2>/dev/null | wc -l)
  echo "$f -> linemon hits=$n"
done

echo "=== before: services keys in the .lua cache ==="
grep -o 'admin/services/[a-z0-9-]*' /tmp/luci-indexcache.*.lua 2>/dev/null | sort -u | head -30

echo "=== clearing ALL luci caches ==="
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.json
rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache
ls -l /tmp/luci-indexcache* 2>/dev/null || echo "(all cleared)"

echo "=== reload rpcd + uhttpd ==="
/etc/init.d/rpcd reload 2>/dev/null || /etc/init.d/rpcd restart 2>/dev/null
sleep 2
/etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart 2>/dev/null
sleep 2

echo "=== after: caches regenerated? ==="
ls -l /tmp/luci-indexcache* 2>/dev/null || echo "(none yet - will regenerate on first LuCI request)"
