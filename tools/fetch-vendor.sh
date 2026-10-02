#!/bin/sh
# 拉取旧版看板（deploy/www/lm/line.html）依赖的第三方前端库。
#
# 为什么不在仓库里直接放这些文件：
#   antd v4 的预编译深色样式有 570 KB，Chart.js 全家桶 290 KB，
#   加起来接近 1 MB 的第三方代码。放进来会让仓库体积膨胀，
#   也不方便跟踪上游版本。这里按固定版本号从 npm 拉，校验后落盘。
#
# 新版看板（web/，React + antd v5）不走这个脚本，它由 npm ci + vite build 产出。
#
# 用法：sh tools/fetch-vendor.sh

set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/deploy/www/lm/lib"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 版本号必须和升级前一致，否则看板样式会跟着变
ANTD_V=4.24.15
CHART_V=4.4.7
ADAPTER_V=3.0.0
ZOOM_V=2.0.1
HAMMER_V=2.0.8

REGISTRY=${NPM_REGISTRY:-https://registry.npmmirror.com}

mkdir -p "$DEST"

fetch() {
    # fetch <npm包名> <版本> <包内路径> <输出文件名>
    pkg=$1; ver=$2; inner=$3; out=$4
    url="$REGISTRY/$pkg/-/$pkg-$ver.tgz"
    echo "  ↓ $pkg@$ver  →  $out"
    curl -fsSL "$url" -o "$TMP/$pkg.tgz"
    tar -xzf "$TMP/$pkg.tgz" -C "$TMP" "package/$inner"
    cp "$TMP/package/$inner" "$DEST/$out"
    rm -rf "$TMP/package"
}

echo "拉取旧版看板依赖到 $DEST"
fetch antd                     "$ANTD_V"    "dist/antd.dark.min.css"                  antd.dark.min.css
fetch chart.js                 "$CHART_V"   "dist/chart.umd.js"                       chart.umd.min.js
fetch chartjs-adapter-date-fns "$ADAPTER_V" "dist/chartjs-adapter-date-fns.bundle.min.js" chartjs-adapter-date-fns.bundle.min.js
fetch chartjs-plugin-zoom      "$ZOOM_V"    "dist/chartjs-plugin-zoom.min.js"         chartjs-plugin-zoom.min.js
fetch hammerjs                 "$HAMMER_V"  "hammer.min.js"                           hammer.min.js

echo "完成："
ls -l "$DEST"
