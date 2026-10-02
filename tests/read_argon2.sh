#!/bin/sh
f=/usr/lib/lua/luci/view/themes/argon/header.htm
echo "=== lines 135-200 ==="
awk 'NR>=135 && NR<=200 { printf "%4d| %s\n", NR, $0 }' "$f"
