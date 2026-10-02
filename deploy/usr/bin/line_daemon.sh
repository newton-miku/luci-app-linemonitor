#!/bin/sh
# line_daemon.sh — 采集调度：延迟每 INTERVAL_MONITOR 秒一次，TCP 流每 INTERVAL_TCP 秒一次
#
# 间隔值来自 /etc/line-monitor/targets.conf，每个采集周期重新加载一次，
# 所以在看板上改间隔不用重启服务（最多等一个周期生效）。
#
# 为什么 line_monitor.sh 要丢到后台跑:
#   它一次要串行做很多次 ping / curl，在某个出口不通的情况下要跑 20~30 秒。
#   若同步等待，tcp_stream.sh 的 5 秒周期会被堵出几十秒空档，实时流那一页就断片了。
#   锁文件防止上一轮还没跑完就叠加下一轮；锁超过 120 秒视为残留（上轮崩了）强制清除。

CONF=/etc/line-monitor/targets.conf
[ -f "$CONF" ] && . "$CONF"

INTERVAL_MONITOR=${INTERVAL_MONITOR:-60}
INTERVAL_TCP=${INTERVAL_TCP:-5}
INTERVAL_RATE=${INTERVAL_RATE:-2}
LOCK=/tmp/lm_monitor.lock

rm -f "$LOCK"   # 清掉上次异常退出可能留下的锁

last_monitor=0
last_tcp=0
last_rate=0

while true; do
    now=$(date +%s)

    if [ $((now - last_monitor)) -ge "$INTERVAL_MONITOR" ]; then
        # 每个周期重读一次配置，改间隔不用重启（配置写坏了就沿用上一份值）
        if [ -f "$CONF" ]; then
            . "$CONF"
            INTERVAL_MONITOR=${INTERVAL_MONITOR:-60}
            INTERVAL_TCP=${INTERVAL_TCP:-5}
            INTERVAL_RATE=${INTERVAL_RATE:-2}
        fi

        if [ -f "$LOCK" ]; then
            lock_ts=$(cat "$LOCK" 2>/dev/null || echo 0)
            [ $((now - lock_ts)) -gt 120 ] && rm -f "$LOCK"
        fi
        if [ ! -f "$LOCK" ]; then
            echo "$now" > "$LOCK"    # 先落锁再起子进程，避免子进程先删锁造成竞态
            (
                sh /usr/bin/line_monitor.sh >/dev/null 2>&1
                rm -f "$LOCK"
            ) &
        fi
        last_monitor=$now
    fi

    if [ $((now - last_tcp)) -ge "$INTERVAL_TCP" ]; then
        sh /usr/bin/tcp_stream.sh >/dev/null 2>&1
        last_tcp=$now
    fi

    # 速率采样写 /tmp（RAM），不磨 flash；前端 2~3 秒轮询一次即可
    if [ $((now - last_rate)) -ge "$INTERVAL_RATE" ]; then
        sh /usr/bin/lm_rate.sh >/dev/null 2>&1
        last_rate=$now
    fi

    sleep 1
done
