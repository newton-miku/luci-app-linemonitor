#!/usr/bin/env python3
# 给「内置蜂窝」的 WEBUI 标签页加一个「飞书 Webhook」输入框，
# 并让「应用并重启服务」按钮把它写进 /usr/bin/smstrun-feishu.conf 后重启转发进程。
#
# 顺带修两个原固件的问题：
#   1) 界面上的「PPS+平台转发Token」(wechat_webhook) 存进 uci 后没有任何代码把它
#      写进 /usr/bin/smstrun.conf，所以那套转发其实一直是断的。这里一并补上。
#   2) 按钮原本是 inputstyle="apply"，只跑 write 回调、不保存表单，
#      用户填的 Token / URL 一刷新就没了。改成 "saveapply"（保存并应用）。
#
# 幂等：重复执行不会重复插入。

import io
import os
import shutil
import sys

TARGET = "/usr/lib/lua/luci/model/cbi/modem.lua"
BACKUP = "/root/cell-sms-backup/modem.lua.bak"

OPTION_ANCHOR = 'wechat_webhook = section:taboption("WEBUI", Value, "wechat_webhook"'
OPTION_INSERT = (
    '\nfeishu_webhook = section:taboption("WEBUI", Value, "feishu_webhook", '
    'translate("飞书 Webhook"),\n'
    '    translate("在飞书群里添加「自定义机器人」，把生成的 Webhook 地址整条粘进来'
    '（形如 https://open.feishu.cn/open-apis/bot/v2/hook/xxxx）。留空则继续走 PPS+。"))\n'
    'feishu_webhook.rmempty = true\n'
)

STYLE_OLD = 'apply_notifications_websocket.inputstyle = "apply"'
STYLE_NEW = 'apply_notifications_websocket.inputstyle = "saveapply"'

WRITE_ANCHOR = '    -- **删除旧的 config.json 并重新创建**'
WRITE_START_MARK = '    -- **同步短信转发配置：飞书优先，其次 PPS+**'

WRITE_INSERT = '''    -- **同步短信转发配置：飞书优先，其次 PPS+**
    -- 只从 self.map 取，不要引用 wechat_webhook/feishu_webhook 这些 option 变量：
    -- write 阶段它们可能还没绑上（实测报 "attempt to index local 'wechat_webhook' (a nil value)"）。
    local feishu_url = self.map:get(section, "feishu_webhook") or ""
    local pps_token = self.map:get(section, "wechat_webhook") or ""
    local feishu_conf = "/usr/bin/smstrun-feishu.conf"
    local pps_conf = "/usr/bin/smstrun.conf"

    -- 这个按钮是 apply 风格，只跑 write 回调、不保存表单。
    -- 顺手把两个字段落进 uci，否则刷新页面输入框就空了。
    local ucix = require("uci").cursor()
    ucix:set("modem", section, "feishu_webhook", feishu_url)
    ucix:set("modem", section, "wechat_webhook", pps_token)
    ucix:commit("modem")
    ucix:close()

    if feishu_url ~= "" then
        nixio.fs.writefile(feishu_conf, feishu_url)
        os.execute("chmod 600 " .. feishu_conf)
    end

    if pps_token ~= "" then
        nixio.fs.writefile(pps_conf, pps_token)
        os.execute("chmod 600 " .. pps_conf)
    end

    -- 重启短信转发进程，让它读到新的配置文件。
    -- 这台固件没有 pkill，用 ps + kill 兜底。
    os.execute("for p in $(ps w | grep '[s]mstrun.py' | awk '{print $1}'); do kill $p 2>/dev/null; done")
    os.execute("rm -f /tmp/smstrun.lock")
    os.execute("nohup python3 /usr/bin/smstrun.py >/tmp/smstrun.log 2>&1 &")

'''


def main():
    if not os.path.isfile(TARGET):
        print("找不到 %s" % TARGET)
        return 1

    with io.open(TARGET, "r", encoding="utf-8", errors="surrogateescape") as fh:
        src = fh.read()

    changed = []

    if "feishu_webhook = section:taboption" in src:
        print("[跳过] 飞书输入框已存在")
    else:
        idx = src.find(OPTION_ANCHOR)
        if idx < 0:
            print("[失败] 找不到 wechat_webhook 的 taboption 定义")
            return 1
        end = src.find("\n", idx)
        if end < 0:
            print("[失败] wechat_webhook 行没有结尾换行")
            return 1
        src = src[: end + 1] + OPTION_INSERT + src[end + 1 :]
        changed.append("输入框")

    if STYLE_OLD in src:
        src = src.replace(STYLE_OLD, STYLE_NEW, 1)
        changed.append("按钮改 saveapply")
    elif STYLE_NEW in src:
        print("[跳过] 按钮已是 saveapply")
    else:
        print("[警告] 没找到 inputstyle 定义，跳过（不影响其他改动）")

    if WRITE_START_MARK in src:
        start = src.find(WRITE_START_MARK)
        end = src.find(WRITE_ANCHOR, start)
        if end > start:
            src = src[:start] + WRITE_INSERT + src[end:]
            changed.append("替换写 conf 块")
        else:
            print("[警告] 找到旧块开头但找不到结尾锚点，跳过")
    else:
        idx = src.find(WRITE_ANCHOR)
        if idx < 0:
            print("[失败] 找不到 apply_notifications_websocket.write 的锚点")
            return 1
        src = src[:idx] + WRITE_INSERT + src[idx:]
        changed.append("写 conf 并重启")

    if not changed:
        print("无需修改。")
        return 0

    os.makedirs(os.path.dirname(BACKUP), exist_ok=True)
    if not os.path.isfile(BACKUP):
        shutil.copy2(TARGET, BACKUP)
        print("[备份] %s -> %s" % (TARGET, BACKUP))

    with io.open(TARGET, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(src)

    print("[完成] 已修改：%s" % "、".join(changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
