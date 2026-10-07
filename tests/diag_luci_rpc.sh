#!/bin/sh
echo "=== rpcd luci 里的 getRealtimeStats ==="
grep -n "getRealtimeStats" -A 60 /usr/libexec/rpcd/luci | head -90
echo
echo "=== 是否引用 hnat / mtketh / esw ==="
grep -n "hnat\|mtketh\|esw_cnt\|hwnat\|all_entry\|qdma" /usr/libexec/rpcd/luci | head -30