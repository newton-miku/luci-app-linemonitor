#!/bin/sh
echo "=== menu.d ==="
cat /usr/share/luci/menu.d/luci-app-linemon.json
echo
echo "=== acl.d ==="
cat /usr/share/rpcd/acl.d/luci-app-linemon.json
echo
echo "=== indexcache files ==="
ls -l /tmp/luci-indexcache* 2>/dev/null
echo "=== indexcache linemon lines ==="
grep -o 'linemon[/a-z]*' /tmp/luci-indexcache.json 2>/dev/null | sort -u
echo "=== indexcache other views for comparison (wol) ==="
grep -o 'admin/services/wol[/a-z]*' /tmp/luci-indexcache.json 2>/dev/null | sort -u
echo "=== all admin/services keys in indexcache ==="
grep -o 'admin/services/[a-z0-9-]*' /tmp/luci-indexcache.json 2>/dev/null | sort -u
