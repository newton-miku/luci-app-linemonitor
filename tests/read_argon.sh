#!/bin/sh
f=/usr/lib/lua/luci/view/themes/argon/header.htm
echo "=== size ==="
wc -c "$f"
echo "=== grep menu rendering ==="
grep -n 'menu\|node\|children\|slug\|url' "$f" | head -40
echo
echo "=== full file (may be long) ==="
cat "$f"
