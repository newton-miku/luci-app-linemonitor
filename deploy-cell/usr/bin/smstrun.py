import json
import os
import re
import socket
import time
import requests
import subprocess
from datetime import datetime

# 飞书自定义机器人 webhook。填了这个文件就推飞书，不再推 PPS+；
# 两者都填时飞书优先（用户要的是「替代」）。
FEISHU_CONF = "/usr/bin/smstrun-feishu.conf"
TOKEN_CONF = "/usr/bin/smstrun.conf"
TITLE_CONF = "/usr/bin/smstrun-title.conf"
SUMMARY_PATH = "/tmp/smstrunsum.conf"
LOCK_FILE = "/tmp/smstrun.lock"

# tailscale 的 MagicDNS 会把 /etc/resolv.conf 改成指向 100.100.100.100，
# 那台 DNS 一旦不可达，路由器上所有域名都解析不了（ping IP 正常、curl 域名超时）。
# 出网前先用本地 dnsmasq（127.0.0.1）把飞书域名解析一次写进 /etc/hosts 兜底。
HOSTS_MARK = " # smstrun-feishu"


def resolve_via(ns, host):
    """用指定的 DNS 服务器解析域名，返回第一个 IPv4 地址。"""
    for cmd in (['nslookup', host, ns], ['nslookup', host]):
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
        except Exception:
            continue
        ips = re.findall(r"^Address \d+:\s*(\d+\.\d+\.\d+\.\d+)", out, re.M)
        if ips:
            return ips[0]
    return None


def clean_hosts_entry():
    try:
        with open("/etc/hosts", "r") as f:
            lines = f.readlines()
    except Exception:
        return
    kept = [l for l in lines if HOSTS_MARK not in l]
    if len(kept) != len(lines):
        try:
            with open("/etc/hosts", "w") as f:
                f.writelines(kept)
        except Exception as e:
            print("清理 /etc/hosts 失败: ", e)


def ensure_hosts_entry(host):
    """先清掉自己以前写的条目，再判断系统 DNS 是否真的能解析；
    不行就用本地 dnsmasq 兜底写 /etc/hosts。

    必须先清：/etc/hosts 里的条目本身就能让 getaddrinfo 成功，
    不清的话会误判成「系统 DNS 正常」，反手把自己的兜底条目删掉。
    """
    clean_hosts_entry()
    try:
        socket.getaddrinfo(host, 443, socket.AF_INET)
        return True
    except Exception:
        pass
    for ns in ("127.0.0.1", "223.5.5.5", "114.114.114.114"):
        ip = resolve_via(ns, host)
        if not ip:
            continue
        try:
            # 写之前再清一次：转发进程启动与手动重置可能几乎同时跑，
            # 交错时两边都会以为自己是唯一，留下重复行（同一个 IP，无害但不干净）。
            clean_hosts_entry()
            with open("/etc/hosts", "a") as f:
                f.write("%s %s%s\n" % (ip, host, HOSTS_MARK))
            print("系统 DNS 不可用，已把 %s -> %s 写入 /etc/hosts 兜底。" % (host, ip))
            return True
        except Exception as e:
            print("写 /etc/hosts 失败: ", e)
            return False
    print("无法解析 %s，飞书推送可能失败。" % host)
    return False


def read_conf(path, default=None):
    try:
        with open(path, "r") as file:
            val = file.read().strip()
            return val if val else default
    except FileNotFoundError:
        return default


def read_title():
    return read_conf(TITLE_CONF, "CPE短信转发标题未定义")


def write_summary_to_file(count, out):
    current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    try:
        with open(SUMMARY_PATH, 'a') as file:
            file.write(f"本次转发时间: {current_time}\n")
            file.write(f"已完成: {count}次短信转发\n")
            file.write(f"转发内容:\n\n{out}\n")
            file.write("\n")
    except Exception as e:
        print(f"写入文件失败: {e}")


def check_lock(lock_file):
    if os.path.exists(lock_file):
        print("脚本已经在运行中。")
        return False
    try:
        with open(lock_file, 'w') as file:
            file.write(str(os.getpid()))
        return True
    except Exception as e:
        print("无法创建锁文件: ", e)
        return False


def remove_lock(lock_file):
    try:
        os.remove(lock_file)
    except Exception as e:
        print("无法删除锁文件: ", e)


def push_feishu(message, url, title):
    """飞书自定义机器人：post 富文本，title 单独一行，正文整段塞进一个 text 节点。

    第一次失败（多半是域名解析不出来）就先补一次 /etc/hosts 兜底再重试一发。
    """
    payload = {
        "msg_type": "post",
        "content": {
            "post": {
                "zh_cn": {
                    "title": title,
                    "content": [[{"tag": "text", "text": message}]]
                }
            }
        }
    }
    for attempt in (1, 2):
        try:
            response = requests.post(url, json=payload, timeout=15)
            print("Feishu response:\n", response.text)
            try:
                return response.json().get("StatusCode") == 0
            except Exception:
                # 返回体不是 JSON 时退化成看 HTTP 状态码
                return response.status_code == 200
        except Exception as e:
            print("Error occurred (%d/2): %s" % (attempt, str(e)))
            if attempt == 1:
                ensure_hosts_entry("open.feishu.cn")
    return False


def push_pushplus(message, token, title):
    url = "http://www.pushplus.plus/send"
    data = {"token": token, "title": title, "content": message}
    try:
        response = requests.post(url, json=data, timeout=15)
        print("Response:\n", response.json())
        return True
    except Exception as e:
        print("Error occurred: ", str(e))
        return False


def forward():
    if not check_lock(LOCK_FILE):
        return

    try:
        feishu_url = read_conf(FEISHU_CONF)
        token = read_conf(TOKEN_CONF)
        if not feishu_url and not token:
            print("飞书 webhook 和 PPS+ token 都没配，程序退出。")
            print("飞书 URL 写到 %s，PPS+ token 写到 %s。" % (FEISHU_CONF, TOKEN_CONF))
            return
        if feishu_url:
            ensure_hosts_entry("open.feishu.cn")
            print("已启用飞书推送。")
        else:
            print("已启用 PPS+ 推送。")
        print("Enjoy! 已完成测试并开启转发功能，重启后完成开机自启。")

        count = 0
        while True:
            try:
                result = subprocess.run(['sh', '/usr/bin/smstrun.sh'],
                                        capture_output=True, text=True, check=True)
                out = result.stdout
                if "发件人" in out:
                    title = read_title()
                    if feishu_url:
                        push_feishu(out, feishu_url, title)
                    else:
                        push_pushplus(out, token, title)
                    count += 1
                    write_summary_to_file(count, out)
                else:
                    print("未检测到新消息，继续检测...")
            except subprocess.CalledProcessError as e:
                print(f"执行命令失败: {e}. 返回值: {e.returncode}. 错误信息: {e.stderr}")
            except UnicodeDecodeError as e:
                print(f"解码错误: {e}. 尝试重新运行。")
            except Exception as e:
                print("发生未处理异常: ", str(e))
            time.sleep(5)
    finally:
        remove_lock(LOCK_FILE)


if __name__ == '__main__':
    forward()
