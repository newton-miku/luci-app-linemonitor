# 线路质量监测（OpenWrt 双 WAN 延迟监测）

[![build](https://github.com/<你>/<仓库>/actions/workflows/build.yml/badge.svg)](https://github.com/<你>/<仓库>/actions/workflows/build.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

在 OpenWrt 路由器上同时监测**两条出口**的延迟质量，并把内网设备正在跑的 TCP 流按出口归类，
用来定位"请求发出去半天没回应""游戏卡顿"这类问题到底是哪条线路在拖后腿。

- **采集**：`line_monitor.sh` 每 60 秒对每个出口的每个目标测一轮 ICMP / HTTP 延迟，追加到 `history.log`；
  另有 5 秒一轮的 TCP 流采集、2 秒一轮的接口实时速率。
- **看板**：React 18 + Ant Design v5 + ProComponents，按出口自动生成页签，双击线段可缩放，
  底部是时间轴滑块；曲线会区分「正常 / 部分丢包（虚线）/ 完全不可达（断开 + 红点）」。
- **设置**：LuCI 侧栏内嵌的设置页，七个标签页改出口、目标、采集参数、告警推送，保存即生效。
- **告警**：异常延迟或无响应持续若干轮后推送到飞书 / 企业微信 / 钉钉 / Bark / Server酱 / Telegram / 自定义 JSON。

配套还有一个独立的 `deploy-cell/`：把「内置蜂窝」模组的短信转发从 PPS+（pushplus）换成飞书机器人。

## 环境要求

| 项目 | 要求 |
|---|---|
| 路由器 | OpenWrt 21.02 或更新，`aarch64` / `arm` / `mipsel` 均可（纯 shell + busybox） |
| 依赖 | `busybox`、`curl`（带 IPv6）、`ip`（iproute2）、`uhttpd`、`luci-base`；**不需要** python / node / jq |
| 构建看板 | Node.js 20+（只在开发机上，路由器不跑 node） |

原始开发环境：`NRadio-C8-New688`（aarch64，Linux 5.4.255，OpenWrt 21.02 定制固件），
本机 `192.168.66.21/24`，路由器 `192.168.66.1`。
**换路由器要改的是 `deploy/etc/line-monitor/targets.conf` 里的接口名、显示名和 mark 值**，
其余不用动；网络参数下面每节都会说明怎么实测。

## 两条出口（示例环境）

| 接口 | 显示名 | 类型 | v4 地址 | v6 地址 | conntrack mark |
|---|---|---|---|---|---|
| `eth1` | 移动 | 蜂窝 CPE（华为，DHCP） | `192.168.8.114/24`（会变） | `2409:8970:9d31:4f78::/64` 下发 | `256` |
| `pppoe-wan2` | 电信 | PPPoE 拨号 | `100.81.x.x` | `240e:358:a001:e066::/64` 下发 | `512`、`768` |

上表是**我这台路由器的实测值，别照抄**。`mark` 值一定要自己测：

```sh
ip route get 1.1.1.1 mark 256   # 看真实出口是哪个 dev
```

`eth1` 的地址由蜂窝模块下发，**不是固定的**（实测从 `.112` 漂到过 `.114`）。
配置里它的源 IP 写 `auto`，采集时现读——写死会让源地址策略路由失效，详见踩坑记录第 19 条。
**v6 同理**：前缀由运营商下发，采集时用 `v6_src_of()` 现读该出口的全局 v6 地址，
不能绑接口名（PPPoE 会 `Permission denied`），详见踩坑记录第 42 条。

LuCI 里 `network.wan2_6` 挂在 `@wan2` 上（`proto=dhcpv6`），但 v6 地址实际落在 `pppoe-wan2`，
所以配置里写 `pppoe-wan2` 是对的。

出口行还有第 5 个字段**类型**（`v4` / `v6` / `both`），决定这个出口测哪一类目标；
留空按 `both` 算，所以老的配置不改也能跑。

## 看板

**新版**（React + Ant Design v5 + ProComponents，本机 Vite 构建）：`http://192.168.66.1/lm/app/index.html`。
LuCI 侧栏「服务选项 → 线路监测 → 延迟看板」嵌的就是这个。
源码在 `web/`，改完 `npm run build` 再 `deploy/install.sh` 就会把产物铺到 `/www/lm/app/`。

**旧版**（单文件 HTML + 手写 antd 类名 + 本地 chart.js）：`http://192.168.66.1/lm/line.html`。
功能等价、不依赖构建，**作为退路保留**。两边读的是同一份 `history.log` / `config.json` / `tcp.json`。

两版都是**标签页按出口自动生成**，不是写死的：

- **总览** — 各出口的平均延迟卡片（带迷你趋势）、IPv6 平均延迟卡片、各目标延迟对比柱状图
- **每个出口一页，页里 IPv4 / IPv6 各占一张卡** — 页名就是出口的显示名（如「移动」「电信」）。页里画几块由该出口的**类型**决定：
  `both` 出两张卡（`移动 · IPv4` / `移动 · IPv6`），`v4` / `v6` 就只出对应的那一张。
  每张卡各有自己的曲线、开关、时间轴和统计表——合并成一张图时 v6 只能靠虚线区分，
  十几条线叠在一起根本看不清，所以干脆拆开。
- **实时TCP流** — 内网设备发起的 TCP 流，标注出口、服务名、状态；卡住的 `SYN_SENT` 整行标红

总览页顶部还有一张 **`实时速率`** 卡：`lm_rate.sh` 每 2 秒读一次 `/proc/net/dev` 的累计计数器，
与上一次相减除以间隔得到各接口的 rx/tx 速率，前端每 2 秒拉一次 `/cgi-bin/lm-rate`。
默认采 `eth1 pppoe-wan2 br-lan` 三个口（`RATE_IFACES` 可改，留空就只采出口）。
接口名到显示名的映射跟看板一样取自 `EXITS` 的第二字段，`br-lan` 这种不在出口列表里的就原样显示接口名。
数字是**最近一个采样间隔的平均值**，不是瞬时值；空闲时的几 KB/s 属于协议开销与后台同步。
**结果写 `/tmp/lm_rate.json`（RAM）**——2 秒一次往 overlay 上写会把 flash 磨坏。

统计表跟着每条出口页走，粒度是**线路 × 协议 × 目标**；总览页那张表把所有出口拼在一起，用「线路」列分组。
IPv6 卡片显示的是**平均延迟数字**（不是「可达/不可达」——那个词没信息量，有数字就给数字）。

出口写了几个、是什么类型，页签就长什么样——增减出口只要在设置页改一行，看板刷新后自动排布。
旧版的「IPv6表」合并页已经取消：v6 曲线现在跟自己的出口待在同一页里。

交互：滚轮缩放、Shift+拖动平移、双击还原缩放、`〰 平滑` 切换单调插值。
缩放与平移的范围都被夹在实际数据之内，右边界最多停在最新一个采集点；拖过时间轴之后，
统计窗口的分段按钮会全部取消选中——此时图与表的口径都由拖动决定，不再看预设窗口。

**底部时间轴滑块**（参考 Ant Design Pro 分析页的 `dataZoom`）：每张图下面一条轨道加两个把手，
左右各显示当前窗口的起止时间，右侧有 `重置窗口`。**拖动改的是全局时间窗口**——
所有出口、所有区块、每一张统计表都按同一个窗口重算；表头那排
`1 小时 / 6 小时 / 24 小时 / 全部` 是同一个窗口的另一种输入方式，点它会反过来推动滑块。
一旦手动拖过滑块，这排按钮就全部取消选中（此时窗口由手势决定，不属于任何预设档），
也不再高亮。双击图表或点 `重置窗口` 等价于「全部」。窗口只在整个数据范围内取值，拖不出空白区。

**曲线上的三种线型**（见踩坑 33~35）：

- **断开** — 这一时刻完全不可达（`FAIL`）。断点会被压成一个空位，曲线在那里真的断开，
  不会平滑跨过去；段起点还标一个红点，连续失败只标第一个。
- **虚线** — 有丢包但不是全丢（ICMP 三包里丢了一两个）。值仍然有效，所以照画，
  但线型改成虚线表示「这次数据不靠得住」。v4 的丢包段是 `[5,4]`；
  **v6 目标整条本来就是虚线**，它的丢包段用更密的 `[2,3]`，两种信息不互相遮蔽。
- **实线** — 完整成功的一次采集。

看板右上角有 `⚙ 设置` 入口，直接跳到设置页改出口、目标与采集参数。

新版看板是**真的在跑 antd v5 和 ProComponents**：`PageContainer` 做页头与页签、
`ProCard` / `StatisticCard`（`chartPlacement="bottom"`，就是 Pro 分析页那张「数字 + 迷你图」的写法）做卡片、
`ConfigProvider theme.darkAlgorithm` 提供深色 token。图表仍然用 Chart.js——
断线、丢包虚线、失败红点、缩放边界这几套逻辑已经在旧版调好了，
换成 G2 等于全部重写，不值当。为什么不上 `@ant-design/pro-layout` / `ant-design-pro`，
见下面的「界面风格」一节。

旧版看板引的是 antd v4.24.15 的官方预编译样式 `lib/antd.dark.min.css`（570 KB），纯 CSS 引入、不需要构建，
页面直接写 `.ant-card` / `.ant-table` 这些类名。两份产物互不影响。

图表库（Chart.js / date-fns adapter / hammer / zoom 插件）与 antd 样式**全部本地托管**
（旧版在 `/www/lm/lib/`，新版打进 `/www/lm/app/assets/`），
不依赖外网 CDN —— 线路本身出问题时看板必须还能打开。

## OpenWrt 界面入口

LuCI 侧栏 **服务选项 → 线路监测** 下挂两个标签页：`延迟看板`（嵌 `/lm/app/index.html`）、`监测设置`（嵌 `/lm/config.html`）。
也可以在浏览器直接访问 `/cgi-bin/luci/admin/services/linemon/status`。

实现方式（本固件 LuCI 是 `git-23.098` 客户端渲染版，和教程里常见的服务端 `.htm` 模板不是一回事）：

- `menu.d/luci-app-linemon.json` 注册菜单节点，`action.type = view` + `path = linemon/status`。
- 视图**必须**放 `/www/luci-static/resources/view/<path>.js`（客户端 JS 模块，`'require view'` + `view.extend({render})`），
  放 `/usr/lib/lua/luci/view/<path>.htm` 会 404 报 `http error 404 while loading class file`。
- 视图内容就是 `E('iframe', { src: '/lm/app/index.html' })`，抄的是同固件 `ttyd/term.js` 的写法。
- 改完菜单要 `rm -f /tmp/luci-indexcache.*`（缓存文件名带随机后缀，写死名字删不掉）+ `/etc/init.d/rpcd reload`。

## 统计

每个标签页底部都有一块统计表，**粒度是「线路 × 协议 × 监测目标」**。出口页里 IPv4 与 IPv6
各占一张卡、各带一张表；总览页把四条线路（移动 (IPv4) / 移动 (IPv6) / 电信 (IPv4) / 电信 (IPv6)）
的全部目标列在一张表里，用左侧的线路列分组。

四档时间窗：`1 小时` / `6 小时` / `24 小时` / `全部`，选择记在浏览器里。
窗口边界按时间戳算，不依赖采集间隔配置。**这四档同时也是曲线图的窗口**——
两条曲线页底部那条时间轴滑块拖出来的区间，和统计表用的是同一个 `xRange`，
所以图和表的数字永远对得上。

九列：样本（有效 / 总）、丢包率、平均、p50、p95、p99、最大、波动σ。

- **丢包率**取窗口内每次采集丢包百分比的平均，配色分三档：`< 0.05%` 当作干净（显示 `0%`、不标色）、`< 1%` 橙色提示、`>= 1%` 红色告警。
  早期版本一律 `> 0` 就标红，会把四舍五入后显示成 `0.0%` 的极小值也烧成红色，自相矛盾。ICMP 类目标若被运营商限速会长期显示高丢包，那是限制不是线路故障。
- **平均与分位数**只统计成功样本（`FAIL` 不计入）。分位数用线性插值：`idx = (n-1)*p`。
- **波动σ**是成功样本的样本标准差（除以 `n-1`），用来区分「稳定但慢」和「忽快忽慢」。
- **最大**和**波动σ**两列另有橙红配色，阈值在设置页可改（默认 `最大 300 / 1000 ms`、`σ 50 / 200 ms`）：
  小于预警值是本色，超过预警值橙色，超过告警值红色。这两列不像丢包率那样有天然分界，
  各目标基线差得远（DNS 一二十毫秒、网页几百毫秒），所以默认值按真机实测取的，觉得吵就在设置页调高。

## 设置页

`http://192.168.66.1/lm/config.html`

东西多了以后分成了七个标签页：**基本 / 出口 / 监测目标 / 采集参数 / 告警推送 / 配色阈值 / 配置预览**。
底部的「保存并生效 / 放弃修改」是常驻的，切到哪一页都能点。

能改的东西全部落在一个文件里：`/etc/line-monitor/targets.conf`

- 看板标题、副标题
- 出口表（接口名 / 显示名 / 源IP / mark / **类型**）
- 内网网段（CIDR，可留空自动识别）
- 三类监测目标（ICMP / HTTP / IPv6）
- 六个采集参数（ping 包数、curl 超时、历史保留行数、公网 DNS、两个采集间隔）
- 统计表配色阈值（最大延迟与波动σ 的预警值 / 告警值，四个数）
- 异常推送（见下一节）

**出口的「接口名」是从路由器现读的**：点那个输入框会列出本机所有接口
（`GET /cgi-bin/lm-config?ifaces`，后面带当前 IPv4 地址或「未启用」），
既能从列表里挑，也能直接手打。所以插了新网卡、PPPoE 拨号成功之后刷新页面就能选到。

**「类型」是下拉选的**（`IPv4 + IPv6` / `仅 IPv4` / `仅 IPv6`），它同时影响采集和看板：
采集脚本只测该类型对应的目标，看板那一页也只画对应的曲线。
只走 v6 的接口选「仅 IPv6」能省掉一半采集时间。类型留空按 `IPv4 + IPv6` 算。

**内网网段填 CIDR，留空就自动识别**。自动识别的顺序是
`uci get network.lan.ipaddr` + `netmask` → 该接口 device 的实际地址（默认 `br-lan`）。
本机实测得到 `192.168.66.1/255.255.255.0`，配置里保持留空即可，换固件换网段都不用改。

它只影响「实时TCP流」页挑哪些连接算内网发起的。**匹配是按位比较，不是字符串前缀**——
`/8 /16 /22 /25 /32` 都算得对，`192.168.66.0/24` 不会像前缀匹配那样把
`192.168.67.x` 也吞进来。多个网段用空格隔开：`LAN_NETS="192.168.66.0/24 10.0.0.0/8"`。
`tests/test_lan_cidr.sh` 用 `/25` 和 `/16` 这两个能区分对错的掩码卡住了这段逻辑。

「配置预览」页实时显示将要写入的 conf 全文，点「保存并生效」通过
`POST /cgi-bin/lm-config` 原子写入（先写 `.tmp` 再 `mv`，旧文件留一份 `.bak`），
并立刻重建 `/www/lm/config.json`。

**采集脚本每轮都重新读取配置**，所以改完不用重启服务，下一个采集周期就生效
（例外：`INTERVAL_MONITOR` / `INTERVAL_TCP` 由守护进程启动时读一次，改了要
`/etc/init.d/linemon restart`）。也可以直接 `vi /etc/line-monitor/targets.conf`。

## 异常推送（Webhook）

线路出问题时推消息到手机或群里。逻辑在 `/usr/bin/lm_alert.sh`，由 `line_monitor.sh`
每轮采集完调用——它读的就是 `history.log` 刚写进去的最后一行。

**先配再测**：在设置页「告警推送」页填好、点「保存并生效」，再点「发送测试消息」。
测试走 `GET /cgi-bin/lm-config?alerttest`，用的是磁盘上那份配置，所以没保存的改动测不到。
总开关和「恢复时是否推一条」都是 antd 的 Switch（`<button role="switch">`），
`aria-checked` 就是落盘的 `1`/`0`，键盘 Space 也能按。

支持的推送类型（`ALERT_TYPE`）：

| 类型 | `ALERT_URL` | `ALERT_TOKEN` |
|---|---|---|
| `json` | 自建服务 / n8n / Node-RED 的地址，收 `{"title":…,"text":…}` | 不用 |
| `wecom` | 企业微信群机器人完整 webhook | 不用 |
| `dingtalk` | 填到 `access_token=` 为止 | access_token 的值 |
| `feishu` | 飞书自定义机器人完整 hook | 不用 |
| `serverchan` | `https://sctapi.ftqq.com/<key>.send` | 不用 |
| `bark` | 服务地址（默认 `https://api.day.app`） | device key |
| `telegram` | `chat_id` | bot token |

**判定与去抖**（这四个参数是重点）：

- `ALERT_MAX_MS` —— 单次延迟超过这个值算异常，默认 300ms；不可达（`FAIL`）和部分丢包也算
- `ALERT_DEBOUNCE` —— 连续几次异常才推第一条，默认 3 次 ≈ 3 分钟。**这道闸门是必需的**：
  移动线路每隔几十分钟会有一次 1 秒左右的尖峰，单次就报会一直响
- `ALERT_COOLDOWN` —— 一直没恢复时多久再提醒一次，默认 1800 秒；填 `0` 表示只在首次和恢复时各推一条
- `ALERT_SCOPE` —— 默认 `v4`。当前移动和电信的 IPv6 目标常年不可达，全报会一直响

同一轮里多个目标出问题是**合并成一条消息**发出去的，不会刷屏。
状态存在 `/tmp/lm_alert.state`（每行 `<键> <状态> <连续次数> <上次推送时间>`）——
放 `/tmp` 是故意的：掉电即忘，免得每分钟擦一次 flash；代价是重启后会重新走一遍去抖。

在路由器上可以直接看状态：

```sh
/usr/bin/lm_alert.sh --status   # 各目标当前是 ok 还是 bad、连续几次、上次什么时候推的
/usr/bin/lm_alert.sh --test     # 立刻发一条测试消息
/usr/bin/lm_alert.sh            # 手动跑一轮巡检（正常由采集脚本调用）
```

## 自动刷新

看板自己会轮询，不用手动刷新：

| 数据 | 间隔 | 说明 |
|---|---|---|
| `history.log` | 15 秒 | 延迟曲线与统计表 |
| `tcp.json` | 5 秒 | 「实时TCP流」页，只在停在这一页时才轮询 |
| `config.json` | 30 秒 | 内容变了才重绘 |

但**轮询不是直接拉文件**。先用 `HEAD` 取一个轻量指纹（`Content-Length` + `Last-Modified`），
和上次一样就直接返回；只有真出了新采集点才 `GET` 整个文件。原因是本机的 `uhttpd`
**不认条件请求**——实测带上 `If-None-Match` 或 `If-Modified-Since` 照样回 `200` + 全量 body，
所以 `fetch(..., { cache: 'no-cache' })` 那套在这里完全无效，等于每 15 秒推一次 470KB。
换成 HEAD 探针之后，稳态下每次只有约 300 字节，出新数据（每 60 秒一次）才传一次全量。

页面切到后台时三个定时器全部停掉，切回来立刻补一次——省路由器，也省笔记本电池。

## 文件结构

```
deploy/
├── install.sh                    安装/升级脚本（已有 targets.conf 不覆盖）
├── etc/
│   ├── init.d/linemon            procd 服务定义（respawn 3600 5 5）
│   └── line-monitor/targets.conf 唯一配置文件
├── usr/bin/
│   ├── line_monitor.sh           延迟采集（默认 60s）→ /www/lm/history.log
│   ├── tcp_stream.sh             TCP 流采集（默认 5s）→ /www/lm/tcp.json
│   ├── line_daemon.sh            调度循环（后台化，见下）
│   ├── lm_config_json.sh         targets.conf → /www/lm/config.json
│   ├── lm_rate.sh                接口实时速率（默认 2s）→ /tmp/lm_rate.json
│   └── lm_alert.sh               异常推送（去抖 + 恢复通知）
├── usr/share/
│   ├── luci/menu.d/luci-app-linemon.json  LuCI 侧栏菜单定义
│   └── rpcd/acl.d/luci-app-linemon.json   LuCI 权限声明
└── www/
    ├── lm/
    │   ├── app/                      新版看板（Vite 产物，构建时生成，git 忽略）
    │   │   ├── index.html
    │   │   └── assets/               3 个 js + 1 个 css，约 1.3 MB
    │   ├── line.html                 旧版看板（单文件，退路）
    │   ├── config.html               设置页（多标签）
    │   └── lib/                      旧版看板本地资源（tools/fetch-vendor.sh 拉取，git 忽略）
    │                                 4 个图表库 js 约 290KB + antd.dark.min.css 约 570KB
    ├── luci-static/resources/view/linemon/
    │   ├── status.js             LuCI 视图：iframe 嵌看板
    │   └── config.js             LuCI 视图：iframe 嵌设置页
    └── cgi-bin/
        ├── lm-config             GET 读配置 / POST 写配置
        │                         ?ifaces 列接口 / ?alerttest 发测试推送
        └── lm-rate               实时速率（读 /tmp/lm_rate.json，带 no-store）

web/                                新版看板源码（只在开发机上构建，路由器上不跑 node）
├── package.json                    React 18 + antd 5 + @ant-design/pro-components + Chart.js
├── vite.config.js                  base './'（外层是 LuCI iframe，绝对路径会打到 LuCI 根）
└── src/
    ├── main.jsx                    ConfigProvider + darkAlgorithm + 中文 locale
    ├── App.jsx                     PageContainer 页头与页签、全局时间窗口、60s 轮询
    ├── api.js                      读 history.log / config.json / tcp.json
    ├── stats.js                    窗口、分位数、丢包着色
    ├── chart.js                    Chart.js 注册、数据集构造、段级线型、缩放边界
    ├── components/                 LineChart / BarChart / Spark / StatTable / TimeAxis
    └── pages/                      Overview（含实时速率卡） / ExitPage / TcpPage
```

运行时产物（不在仓库里）：`/www/lm/history.log`、`/www/lm/tcp.json`、
`/www/lm/config.json`、`/tmp/lm_ipmap.txt`、`/tmp/lm_monitor.lock`、
`/tmp/lm_alert.state`、`/tmp/lm_rate.json` / `/tmp/lm_rate.state`

仓库里还有：

```
tools/                               构建/检查用的小工具（不部署到路由器）
├── fetch-vendor.sh                  拉旧版看板的第三方库到 deploy/www/lm/lib/
└── check-inline-js.js               抽 HTML 内联 <script> 做语法检查（CI 用）

.github/workflows/build.yml          CI：语法体检 → 构建 → 组装 → 自检 → 发 Release
LICENSE                              MIT
```

`.gitignore` 里排除的 `deploy/www/lm/app/`（前端产物）与 `deploy/www/lm/lib/`（第三方库）
都要在构建阶段生成，见下面「部署」一节。

## 部署

### 方式一：用 CI 打好的包（推荐）

推一个 `v*` tag，GitHub Actions 会构建看板、拉齐第三方库、组装成
`linemon-v1.0.0.tar.gz` 挂到 Release 上，里面**已经包含构建好的前端产物**，
可以在路由器上直接装：

```sh
# 路由器上
wget -O /tmp/lm.tar.gz https://github.com/<你>/<仓库>/releases/latest/download/linemon-<版本>.tar.gz
mkdir -p /tmp/lm && tar -xzf /tmp/lm.tar.gz -C /tmp/lm
sh /tmp/lm/deploy/install.sh
```

也可以从 Actions 页面下 artifact（每次 push 都有，保留 30 天）。

### 方式二：本机构建

克隆后 `deploy/www/lm/app/` 和 `deploy/www/lm/lib/` 是空的
（都在 `.gitignore` 里，前者是构建产物、后者是第三方库），需要先补齐：

```sh
# 1. 新版看板（React + antd v5）
cd web
npm ci               # 用 npm，pnpm 12 会拦 esbuild 的构建脚本
npm run build        # 产物在 web/dist/
rm -rf ../deploy/www/lm/app && mkdir -p ../deploy/www/lm/app
cp -r dist/. ../deploy/www/lm/app/
cd ..

# 2. 旧版看板的第三方库（antd v4 预编译 CSS + Chart.js，约 860 KB）
sh tools/fetch-vendor.sh
```

然后打包上传（把 `192.168.66.1` 换成你的路由器）：

```sh
tar -czf lmdeploy.tar.gz deploy
scp lmdeploy.tar.gz root@192.168.66.1:/tmp/
ssh root@192.168.66.1
  rm -rf /tmp/lmd && mkdir -p /tmp/lmd
  tar -xzf /tmp/lmdeploy.tar.gz -C /tmp/lmd
  sh /tmp/lmd/deploy/install.sh
```

`install.sh` 会把 `deploy/www/lm/app/` 整目录刷到 `/www/lm/app/`（先 `rm -rf` 再铺），
所以升级后不会留下上一版哈希文件名的 js/css。包约 2.3 MB。

安装时会打印一次 `Command failed: Not found`（来自 rc.common，exit code 1 被吞掉），
**不影响功能**，服务照常起来。

升级（保留配置）用 `tests/upgrade.sh`：备份 → 停服务 → 解包 → `install.sh` → 起服务。

### CI 做什么

`.github/workflows/build.yml`，push / PR / tag 都跑：

1. **语法体检** —— 所有 `*.sh` 过 `sh -n`；`*.py` 过 `py_compile`；两个 HTML 里的内联
   `<script>` 抽出来用 `node --check` 过一遍（`tools/check-inline-js.js`）。
2. **构建看板** —— `npm ci && npm run build`，再把 `web/dist/` 铺到 `deploy/www/lm/app/`。
3. **拉第三方库** —— `tools/fetch-vendor.sh` 按固定版本号从 npm 拉旧版看板依赖。
4. **组装 + 自检** —— 打成 tar.gz，然后逐项核对 18 个关键文件是否都在包里，缺一个就红。
5. **发 Release** —— 只有推 `v*` tag 时才走，附件就是上面那个 tar.gz。

本地改完想要同样的检查，跑一遍就行：

```sh
for f in $(find deploy deploy-cell tools -name '*.sh'); do sh -n "$f" || echo "FAIL $f"; done
node tools/check-inline-js.js deploy/www/lm/line.html deploy/www/lm/config.html
```

## 数据格式

`history.log` 每行一次采集，空格分隔的 `键=值,状态`：

```
1790847553 eth1|阿里DNS=67.124,0 pppoe-wan2|阿里DNS=23.776,0 v6-eth1|阿里v6=FAIL,100
```

键是 `<接口名>|<目标显示名>`（IPv6 是 `v6-<接口名>|<目标>`）。
`FAIL,100` 表示 ICMP 测试失败；HTTP 目标失败写 `FAIL,1`。
v4 的 ICMP 目标在部分线路上会被运营商封（标 `FAIL`），这是**限制不是故障**，看板上有说明。

`tcp.json`：

```json
{"ts":1790847579,"streams":[{"src":"192.168.66.21","sport":"7484","dst":"2.17.106.176",
 "dport":"443","iface":"eth1","service":"淘宝","state":"SYN_SENT"}]}
```

`/tmp/lm_rate.json`（实时速率，2 秒一次，掉电即忘）：

```json
{"ts":1790910508,"rates":[{"if":"eth1","label":"移动","rx":5653,"tx":21548},
 {"if":"pppoe-wan2","label":"电信","rx":7506,"tx":14092},{"if":"br-lan","label":"br-lan","rx":17825,"tx":12107}]}
```

`rx`/`tx` 单位是**字节/秒**（前端 `fmtRate()` 换算成 KB/s、MB/s）。

## 踩坑记录

**接口相关**

1. `eth1` 是蜂窝 CPE 出口、`pppoe-wan2` 是电信 PPPoE。早期版本两个标签是反的，
   后来用 LuCI + `ip route get` 实测确认。
2. conntrack 的 mark：`256`→`eth1`、`512`/`768`→`pppoe-wan2`。`512` 出现的条数比另外
   两个都多，早期版本没判它，全落到"未知"。
3. 测电信（`eth1`，源地址 `192.168.8.112`）的 HTTP 目标需要临时策略路由
   `ip rule add from 192.168.8.112 lookup 1 pref 3000`，测完立刻删，否则不对称路由导致连接失败。

**busybox 相关**

4. `/proc/net/nf_conntrack` 的字段：`$6`=TCP 状态、`$7`=src、`$8`=dst、`$9`=sport、
   `$10`=dport，mark 在行尾。**但 `$7`/`$8`/`$9`/`$10` 自带 `src=`/`dst=`/`sport=`/`dport=` 前缀**，
   必须 `substr($7,5)` 或 `${7#src=}` 剥掉再比较，否则 `case "$src" in 192.168.*)` 永远不匹配。
5. busybox 的 `$10` 必须写成 `${10}`。
6. **别用 shell 逐行处理 conntrack**：150+ 行时纯 shell 循环要 4~5 秒，逼近采集周期。
   现在整段用单进程 awk 一次过，耗时 0 秒。
7. awk 里不要用未定义变量做判断（写 `DST` 而不是 `dst` 会导致所有行被跳过）。
8. `ping` 输出解析用 `awk index()+split()`，别用 `sed`/`\/` 转义（busybox 不可靠）。
9. 系统 DNS 走 tailscale 解析不了公网域名，必须 `nslookup <域名> 223.5.5.5`
   （输出为 `Address N: <ip>` 带编号）。
10. 服务名映射要收录域名**全部**的解析结果，否则绝大多数连接会显示"其他"。

**调度相关**

11. `line_monitor.sh` 一次约 26 秒，若同步执行会把 5 秒周期的 TCP 采集堵出几十秒空档。
    现在改成丢后台（`( sh ... ; rm -f "$LOCK" ) &`），并且**先落锁再起子进程**——
    反过来的话子进程删完锁父进程又把锁写回去，锁会永久残留。

**前端相关**

12. `tab` 的 DOM id 是 `tab-wan1`/`tab-wan2`/`tab-ipv6`/`tab-tcp`/`tab-overview`，
    但 `chartState` 的 key 是 `wan1`/`wan2`/`v6` —— 两套命名不通用。
13. chartjs-plugin-zoom 2.0.1 的 `limits` 不可用：不认 `'data'` 关键字，用 `'original'`
    会把范围锁死在页面加载那一刻，新采集的点被挤出画面。现在自己在 `onZoomComplete` /
    `onPanComplete` 回调里夹取。
14. 平移的自动化测试必须用 PointerEvent，合成 MouseEvent 时 hammer.js 的 pan 识别器不响应。
15. `evaluate_script` 里传含中文/内网 IP 的多行 JS 会被环境拦截，把脚本写成文件再用 Node 跑。
16. **侧栏菜单被缓存在 sessionStorage 里，硬刷新清不掉**。LuCI 客户端的 `ui.menu.load()`
    把 `/cgi-bin/luci/admin/menu` 的结果塞进 `sessionStorage`（`luci-session-store` 里的
    `.menu` 字段），之后只读缓存；而 `ui.menu.flushCache()` 只清存储、不清内存单例
    `ui.menu.menu`，单独调它无效。所以新装 app 后「重装没用、硬刷新也没用」是假象，
    关掉标签页重开就好。`status.js` 里做了一次性自愈：树里没有 linemon 就
    `flushCache()` + `menu = null` + `location.reload()`，标记位防循环。
    排查时注意 `scrubMenu()`（在 `ui.js`）会把 `action.type == 'firstchild'`
    且没有任何带 title 的 satisfied 子节点的项标成 `satisfied = false`，
    父菜单项因此消失——但这不是本例的原因。
17. 换 antd 时有几个坑：① `antd.dark.min.css` **只管 `.ant-*` 组件，不管 `body`**——
    页面底色、字体栈、栅格间距全得自己写（见两页 `<style>` 里 `.lm-*` 那部分）。
    ② antd 的表格单元格默认 `padding: 16px 8px`，监控表行多，看着松垮，要收到 `9px 12px`；
    表格还得显式 `width: 100%` 才会撑满内容区（antd 只给 `min-width`）。
    ③ `.ant-tabs` 的滑动指示条（ink-bar）位置要靠 JS 算 transform，纯 CSS 拿不到，
    所以只用了 `.ant-tabs-tab-active` 的文字变色，没要指示条。
    ④ `install.sh` 里拷 `lib/` 必须写 `*` 而不是 `*.js`，否则新增的 antd css 传不上去。
18. **`curl -w '%{time_connect}'` 在连接失败时照样输出 `0.000000`**，光看输出分不出
    「真的 0ms」和「压根没连上」。不检查退出码就会把失败记成合法的 0ms，
    曲线被画成一条假零线（日志里表现为 `微信=0,1`）。现在用退出码判断。
19. **源地址策略路由不能写死 IP**。`eth1` 是蜂窝模块下发的 DHCP 地址，实测一天内
    就从 `192.168.8.112` 变成 `192.168.8.114`；写死的那条 `ip rule` 还挂在那儿，
    却不匹配任何流量——包从 `eth1` 出去、回包按主表默认路由（电信）回来，
    非对称路由让 TCP 握手随机失败，表现为 HTTP 目标「时通时不通」（移动出口的
    微信/淘宝/B站/QQ 曾长期一半超时）。配置里源 IP 写 `auto`，采集时 `ip addr`
    现读；路由表号也按接口反查（原来硬编码 `lookup 1`，会把别的出口塞进移动的表）。
20. **HTTP 目标要带 `Host` 头**。不带时腾讯的服务器直接掐断连接（`curl` 退出码 52，
    服务器空回复），握手其实已经完成。现在 `curl -H "Host: <原域名>"`，
    并把 `rc=52`/`56` 视为握手成功——测的是 TCP 连接耗时，不是网页能不能打开。
21. **iframe 会复用旧文档**。`uhttpd` 只发 `ETag`/`Last-Modified`，不发 `Cache-Control`，
    父页面硬刷新时浏览器常常不重新加载 iframe，因此看不到刚部署的页面。
    两个视图里的 `src` 都带了版本串（`?v=20261002a`），改页面时记得一起改。
22. 目标名不能中途改：douyin.com 曾在配置里叫「字节」，历史日志里混了 556 处两套名字，
    统计表按「线路 × 目标名」分组，同一个目标会被拆成两行。改名要连着 `history.log` 一起改。
23. **本机的 `uhttpd` 不认条件请求**。`fetch(url, { cache: 'no-cache' })` 的本意是
    「每次都向服务器验证、没变就只回 304」，但实测带 `If-None-Match` / `If-Modified-Since`
    照样返回 `200` + 完整 body（477766 字节，一个字节没省）。所以想让轮询跑得快，
    得自己用 `HEAD` 取 `Content-Length` + `Last-Modified` 当指纹，比对通过就直接返回，
    别去 GET。同一个坑对 `tcp.json` 也成立。
24. 前端改完发现看不到新版时，先怀疑缓存：静态文件没发 `Cache-Control`，
    浏览器可能仍用旧副本；而 LuCI 的 iframe 还会额外复用旧文档。
    两个视图里的 `src` 带了版本串（现为 `?v=20261002c`），改页面时一起 bump 就能强制重取。
25. **推送必须去抖**。移动线路每隔几十分钟就有一次 1 秒左右的延迟尖峰，
    单次超阈值就报会一直响。现在是「连续 N 次异常才推第一条，推过之后沉默到恢复」，
    恢复时另推一条。状态文件放 `/tmp`：写 flash 每分钟擦一次受不了，代价是重启后
    会重新走一遍去抖（可接受）。
26. **busybox awk 没有 `strftime`**。想格式化时间戳只能用 `date -d "@$t" '+%m-%d %H:%M'`。
    另外 `printf '%-30s'` 按**字节**补空格，中文一个字两字节，拿它排中文表头会歪，
    表头直接手写空格对齐。
27. **参数兜底**：新加的配置项都用 `: "${ALERT_ENABLE:=0}"` 这样取默认值，
    老版本的 `targets.conf` 不重装也能跑（`install.sh` 有意不覆盖已有配置）。
28. **看板标签页是动态的，改数据结构要连带改成循环**。出口从「写死两个 + 一个合并的 IPv6 表」
    改成「一出口一页」时，有三处写死的 `['wan1','wan2','v6']` 漏改（`loadHist`、
    `checkConfig`、`syncSmoothButtons`），表现是**曲线图全空**——数据在、表格对，只有图是白的。
    新增出口、改出口类型之后，凡是遍历图表的地方都用 `Object.keys(chartState)`。
29. **重建 DOM 之后必须重新 `initLineTab`**。配置一变 `buildTabs()` 会把标签页和 canvas
    整个换掉，旧 `Chart` 实例指向的是已经脱离文档的 canvas。销毁了却不重建，
    页面就只剩空图；所以 `buildTabs()` 末尾直接把新图挂上，`boot()` 里不再重复建。
30. **`?v=` 版本串要跟页面一起改**。现在两个视图都指向 `?v=20261002e`，
    改完 `line.html` / `config.html` 记得同步 bump，否则 iframe 还是拿旧文档（见第 21 条）。
31. **判内网不能做字符串前缀匹配**。原来是 `case "$src" in "$LAN_PREFIX"*)`，只能表达
    「以 `192.168.66.` 开头」——掩码一换就错：`/16` 时 `192.168.67.5` 是内网却判外，
    `/25` 时 `192.168.66.130` 是外却判内。现在按位比较（`int(ip / 2^(32-bits))` 比高位），
    掩码可以是位数也可以是 `255.255.255.0` 形式。**busybox awk 没有 `and()`/`rshift()`**，
    所以用乘加代替左移、除法代替右移——double 在 2^53 以内精确，32 位整数放得下。
32. **antd 的 Switch 不是 `<select>`**，没有 `.value`。状态在 `class` 上
    （`ant-switch-checked`）和 `aria-checked` 上，读写都要走 `classList.contains`。
    另外它的 `ant-switch-inner` 是放 `checkedChildren` 文字的地方，本来可以留空。
33. **曲线断网要断线，不能只是「跳过这个点」**。`parseHistory` 原来在失败时
    `return`（不往数组里放点），结果数组里只剩成功的点——x 间隔拉大，但相邻两点
    仍然相连，Chart.js 照常画一条平滑曲线跨过整段断网，看起来就是「断网处平滑连到
    下一个正常点」。`spanGaps: false` 只在**数组里存在 `y: null` 的元素**时才生效，
    所以失败必须占位压入 `{ x, y: null }`。`renderSparks` 里的 `.filter(Boolean)`
    也是同一个毛病，一并去掉。历史脏数据（见第 34 条）已经落盘，所以 `parseHistory`
    里还要把 `0,1` 也当失败处理。
34. **`curl -w '%{time_connect}'` 在 rc=52/56 时可能压根不填**，`$ms` 会是空串，
    过一遍 `awk` 就变成 `0 1` 写进日志。光靠退出码判断 `0|52|56` 算成功是不够的——
    真机实测移动侧四个 HTTP 目标各有 500+ 条 `=0,1` 脏数据，曲线底部被画成一条假零线。
    现在 `curl_parse` 里值 `<= 0` 一律记 `FAIL 1`（连接耗时不可能真的是 0），
    已落盘的老数据用 `tests/clean_zero.sh` 清洗（`s/=0,1 /=FAIL,100 /g`，改前自动备份
    `history.log.bak-zero`）。
35. **判「部分丢包」不能用 `loss > 0`**。两类目标的第二个字段含义不同：ICMP 记的是
    丢包百分比（三包丢一包 = `33`），HTTP 记的是 `0`/`1` 标志位。按 `> 0` 判会把
    HTTP 的 `1` 全当丢包（真机实测微信 1009 个点里有 531 个被误判成虚线）。
    `line.html` 里用 `LOSSY_MIN_PCT = 10` 分开：ICMP 丢 1/3 = 33 触发虚线，
    HTTP 的 `1` 不触发。**v4 的丢包段用 `[5,4]` 虚线，v6 本身整条就是虚线，
    丢包段改用更密的 `[2,3]`**，两种信息互不遮蔽——靠 Chart.js 4 的
    `segment.borderDash` 回调按段生效（优先级高于顶层 `borderDash`）。
36. **深色主题下原生 `<select>` 的下拉列表是白底浅字**，看不清。加
    `html { color-scheme: dark }` 让浏览器把 option 列表、datalist、滚动条一起
    画成深色；再补一条 `select.ant-input option { background:#1f1f1f }` 兜底老内核。
    另外 `<select class="ant-input">` 的高度会塌成 `auto`，和旁边输入框对不齐，
    显式给 `height:32px; padding:0 11px`。
37. **`buildTabs()` 重建时必须记住当前标签页**。`checkConfig()` 轮询发现配置变了会调
    `loadConfig()` → `buildTabs()`，而重建出来的 pane 是裸的 `class="lm-pane"`，
    于是所有 pane 都丢掉 `active`、页面变成一片空白；就算补上 `active`，用户也会被
    甩回「总览」。现在开头先读 `currentTab`（或 DOM 上现存的 active tab）记下来，
    重建时按它决定谁带 `active`，末尾再对总览 / TCP 这两个静态 pane 补一次。
    同一个坑的第二次踩法：**重建出的 `statBox-*` 是空 div，必须重画统计表**，
    否则切到出口页只有图和滑块、表是空的——`buildTabs()` 末尾因此补了 `renderStats()`。
38. **`tab-ex:eth1~v4` 这种 id 不能写进 CSS 选择器**。冒号是伪类、波浪号是兄弟组合器，
    `document.querySelector('#tab-ex\\:eth1')` 侥幸能跑但极易写错，
    **一律用 `getElementById`**。真机上就有一次 `querySelector('#axis-ex\\:eth1~v4')`
    返回 `null` 导致点击没生效。
39. **隐藏容器里初始化的 Chart.js 尺寸是 0**，`switchTab` 里必须对**该页的所有区块**
    逐个 `resize()`（一个出口页现在有两张图），只 resize 一张的话另一张会一直是空的。
    另外真机 1000+ 点时重绘需要几十毫秒，截图要等一会儿才有内容——
    本地 288 点的沙箱看不出来，别把它当成 bug。
40. **时间轴拖动不要重建 DOM**。`renderTimeAxis()` 会 `innerHTML = ''`，拖动过程中调用会让
    把手掉焦点、手势中断。所以拖动走 `syncTimeAxis()`（只改 `left`/`width` 和 `input.value`），
    且赋值前判断 `document.activeElement !== ins[0]`，别去动用户正按着的那个。
    `loadHist()` 每 15 秒重画一次，那里也加了一道「有焦点在把手上就整套跳过」的闸。
41. **x 轴窗口只能有一个真相**。以前 `statWin`（1h/6h/24h/全部）只作用于统计表，
    图看的是 `min/max`，两边口径能对不上。现在统一成全局 `xRange`：图取它、
    统计表取它、时间轴滑块也取它，`statWin` 退化成「往 `xRange` 里填值的一种快捷方式」。
    `xRangeCustom` 单独记「这个窗口是人拖出来的」，用来决定预设按钮该不该高亮。
42. **`ping6 -I <接口名>` 在 PPPoE 上必然失败**，这是电信 IPv6 「一直 100% 丢包」的真正原因。
    本固件 busybox 1.33 对点对点接口一律返回 `ping6: sendto: Permission denied`——
    包压根没发出去，却被记成了丢包。**改成绑该出口现读的全局 v6 地址**（`v6_src_of()`）：

    ```
    ping6 -I pppoe-wan2         2400:3200::1  ->  Permission denied
    ping6 -I 240e:358:...:89e1  2400:3200::1  ->  0% packet loss, 28ms
    ```

    之所以源地址够用：v6 路由表里每条默认路由自带 `from <前缀>`
    （`default from 240e:358:a001:e066::/64 via ... dev pppoe-wan2`），
    源地址一选定内核自己会选对出口，不需要绑设备。`/^f[cd]/` 要判掉 ULA 和链路本地。
43. **v6 目标要实测，别挑网段地址**。`2402:4e00::`（腾讯 DNSPod 网段）和 `2409:8080::8`
    两条出口都不回包，一开始就选错了。现行目标是
    `阿里v6:2400:3200::1` / `移动v6:2409:8080:1::1` / `国际v6:2620:0:ccc::2`，
    三个在两条出口上都是 0% 丢包。
44. **缩放边界要用插件自己的 `limits`，不能事后夹**。原先是在 `onZoomComplete` /
    `onPanComplete` 里调 `clampXToData()` 把轴拉回数据范围，手感上是「先缩进去、再被弹回来」，
    中途还看得到越界的空白画面。正确做法是给 `plugins.zoom.limits.x` 设
    `{ min, max, minRange }`——插件在**手势进行中**就把范围夹住，是「到边就缩不动」。
    两个坑：① `limits` 只在图表建立那一刻读一次，所以 `loadHist()` 里数据一变就要
    调 `refreshXLimits()` 重贴一遍（实测写成 `'original'` 会锁死在加载那一刻，
    数据涨到 04:02 而轴停在 03:52；`'data'` 这个关键字 2.0.1 不认）；
    ② `minRange: 60000` 兜的是「被夹得比一分钟还窄」，没有它能把窗口缩到 0 宽。
    `clampXToData()` 保留着当兜底，正常路径不会触发。
    实测：120 次滚轮缩小后 `range` 正好停在 60000；300 次放大后 `min/max`
    精确等于首末采集点；平移顶到边界后窗口宽度不变。
45. **`pnpm 12` 装不了这个工程**。`pnpm install` 报 `ERR_PNPM_IGNORED_BUILDS`
    （`Ignored build scripts: esbuild@0.21.5`），而 `package.json` 的 `pnpm` 字段和
    `pnpm-workspace.yaml` 的 `onlyBuiltDependencies` **都已经不再被读取**
    （警告原文：`The "pnpm" field in package.json is no longer read by pnpm`），
    esbuild 缺原生二进制就构建不了。直接用 `npm install`（npm 不拦构建脚本）。
    切回来之前要删掉 `node_modules`、`pnpm-lock.yaml`、`pnpm-workspace.yaml`，
    否则两套锁定文件互相打架。
46. **`vite.config.js` 的 `base` 必须是 `'./'`**。页面挂在 `/lm/app/` 下、外面还套着
    LuCI 的 iframe，绝对路径的资源引用会打到 LuCI 根目录（`/assets/xxx.js` → 404）。
47. **antd v5 的组件导出位置要认准**。`ProCard` 来自 `@ant-design/pro-components`，
    不是 `antd`；`CheckableTag` **不在** antd 的根导出里，要写
    `import { Tag } from 'antd'; const { CheckableTag } = Tag;`。
    构建时报 `"XXX" is not exported by "node_modules/antd/es/index.js"` 就是这个原因。
48. **antd v5 的 `Table` 合并单元格要用 `onCell`，不能用 render 返回 `{children, props}`**。
    写 `onCell: (row) => ({ rowSpan: row.__first ? spans[row.gid] : 0 })`，
    `0` 表示「这一格被上面那格吃掉」。旧写法静默失效，列不会合并。
49. **图表组件只在挂载时建一次图，之后原地换数据**。`LineChart` 如果跟着 props 重建
    `new Chart()`，用户拖好的时间窗口、缩放位置每次刷新都会丢掉。
    正确做法是 `useEffect` 里只改 `c.data.datasets` + `refreshLimits(c, span)` + `c.update('none')`；
    外部 `range` 变化也要先比对（差 <1ms 就跳过），否则 `zoomScale` 会和用户的手势打架。
50. **`tcp.json` 的结构是 `{"ts": …, "streams": [...]}`**，不是裸数组、字段也不叫 `flows`。
    照猜测写页面会静默显示「0 条」。先 `cat` 一眼真实文件再写解析。
51. **预设窗口按钮高亮不能看窗口宽度**。原先用「当前宽度 == 预设宽度」判高亮，
    结果用户拖到刚好 6 小时，「6 小时」会莫名亮起来，再点它又没反应。
    要单独用一个 `rangeCustom` 布尔标记「这次是人拖出来的」，预设按钮只在它为 false 时高亮。
52. **默认时间窗口用「全部」**。Pro 分析页那条 dataZoom 滑块是铺满轨道的；
    一上来只留最后 1 小时的话两个把手会挤在右端一小截，既看不出滑块的存在、
    也不像 demo。默认给全量，用户点 `1 小时 / 6 小时` 再收窄。
53. **`ps` 里看到两个 `line_daemon.sh` 是正常的，不是进程泄漏**。
    `line_daemon.sh` 第 41–44 行用 `( sh /usr/bin/line_monitor.sh; rm -f "$LOCK" ) &`
    把采集丢到后台，那个 `( ) &` 子 shell 的 argv 仍然是 `line_daemon.sh`，
    所以 `ps w` 会同时列出父进程和这个子 shell。判断有没有真的重复采集要看
    `history.log` 的时间戳有没有重复（`tail -30 … | awk '{print $1}' | sort | uniq -d`），
    不是数进程个数。锁文件 `/tmp/lm_monitor.lock` 保证上一轮没跑完不会叠加下一轮。
54. **速率文件的路径必须和 CGI 读的一致，而且不能落在 overlay 上**。`lm_rate.sh` 初版
    把结果写 `/www/lm/rate.json`（overlay），而 `/cgi-bin/lm-rate` 读 `/tmp/lm_rate.json`——
    两边对不上，接口一直返回空壳 `{"ts":0,"rates":[]}`，看板上那张卡永远没数据。
    统一到 `/tmp/lm_rate.json` 之后立刻正常。更重要的是**2 秒一次的采样绝不能写 overlay**：
    flash 有擦写寿命，这种频率写下去迟早写坏，而且 `/tmp` 掉电即忘正好符合「实时速率」的语义。
55. **`Copy-Item -Recurse -Force` 不会删除目标目录里的旧文件**。`vite build` 每次产出的
    hash 文件名都不同，直接覆盖着拷会让本地 `deploy/www/lm/app/assets/` 里堆着上一版的
    `index-*.js`。必须先 `Remove-Item -Recurse -Force deploy\www\lm\app` 再拷。
    （路由器侧不受影响，因为 `install.sh` 里是先 `rm -rf /www/lm/app` 再铺。）
56. **Tailscale 宣告了客户端自己所在的网段，会把到路由器的路由抢走**。路由器
    `tailscale debug prefs` 的 `AdvertiseRoutes` 是 `["192.168.66.0/24"]`，
    而 Windows 客户端（`192.168.66.21`）本身就处在这个网段里；一连上 Tailscale，
    同前缀长度下 tailscale 接口的路由会压过本地以太网，于是 `192.168.66.1` 走隧道出去，
    回包又因为 `ts-postrouting` 只对 `mark 0x40000` 做 SNAT 而回不来——表现就是
    「一连接就打不开路由器界面」。修法：路由器 `tailscale set --advertise-routes=`，
    或客户端关掉「接受子网路由」。诊断看 `route print -4 | findstr 192.168.66`
    与 `tracert -4 -d -h 3 192.168.66.1`。

## 界面风格

新版看板**直接跑 antd v5 + ProComponents**，不再需要「手写类名去模仿 Pro」：

- `PageContainer`（`ghost`、隐藏面包屑）承载页头与页签
- `ProCard` 做出口页的卡片容器；`StatisticCard` + `chartPlacement="bottom"` 做总览的「数字 + 迷你趋势图」，
  就是 Pro 分析页那四张卡片的写法
- `ConfigProvider` + `theme.darkAlgorithm` 提供深色 token（`colorPrimary #1668dc`、
  `colorBgLayout #000`、`colorBgContainer #141414`、`borderRadius 8`），
  components 里把 `Card.headerHeight` 定成 56、`Table.cellPaddingBlock` 定成 12
- 曲线仍用 **Chart.js**，配色用 **AntV G2 的 categorical 色板**（`#5B8FF9` `#5AD8A6` `#F6BD16`…），
  Pro 分析页那几张折线图用的就是它

为什么用 `@ant-design/pro-components` 而不是 `@ant-design/pro-layout` / `ant-design-pro` 整套：
后者是 umi + React 的路由型脚手架，要生成登录/权限/多页骨架，且 `pro-layout` 的 `package.json`
里 `style` 字段为空（v7 走 `@ant-design/cssinjs` 运行时注入）、`peerDependencies` 要求 `antd` +
`react` + `react-dom`；而我们的页面是**单个页面嵌在 LuCI 的 iframe 里**，
再套一层 Pro 的侧栏 + 顶栏会变成三层导航。所以只取它的**组件**，不取它的**骨架**。

旧版看板（`line.html`）的观感是**纯 CSS 手写**还原的：引 antd v4.24.15 的官方预编译深色包
`lib/antd.dark.min.css`（570 KB，文件头有 `/*! antd v4.24.15 Copyright 2015-present, Alipay, Inc. */`），
只写 `.ant-*` class、零 JS 依赖、不需要构建。它保留在那里当退路。

| Pro 的特征 | 旧版怎么还原 |
|---|---|
| 卡片圆角 8 + 极淡投影 + 细边框 | `.ant-card { border-radius:8px; box-shadow:0 1px 2px 0 rgba(0,0,0,.45) }`（v4 默认圆角是 2） |
| 卡片头 56px、标题 16px/600 | `.ant-card-head { min-height:56px }` + `.ant-card-head-title` |
| 卡片体留白 24px | `.ant-card-body { padding:24px }` |
| 统计卡「标签 + 大数字 + 分隔线下的一行小字」 | `.ant-statistic` + `.lm-detail`（`border-top:1px solid #303030`） |
| 表格行高偏大、表头底色抬一档 | 单元格 `padding:12px`、表头 `background:#1f1f1f` |
| PageContainer 的「标题 + 一行描述 + 右侧操作」 | `.lm-head` + `.lm-sub` + `.lm-head-right` |
| 分析页折线图底部的 dataZoom 滑块 | `.lm-timeaxis`（轨道 + 双把手 + 选中段高亮 + 两端时间标签） |

配色同样统一到 **antd v5 的深色语义 token**（Pro 基于 v5）：主色 `#1668dc`、
success `#49aa19`、warning `#d89614`、error `#dc4446`、bgLayout `#000`、
bgContainer `#141414`、bgElevated `#1f1f1f`、borderSecondary `#303030`。

## 辅助脚本（tests/）

| 脚本 | 用途 |
|---|---|
| `check_js.js` | Node 抽取 HTML 内联 `<script>` 做语法检查（不执行） |
| `upgrade.sh` | 升级部署：备份 → 停服务 → 解包 → 安装 → 起服务 |
| `verify_upgrade.sh` | 核对配置项、config.json、CGI、tcp.json 出口分布 |
| `verify_alert.sh` | 核对告警脚本部署、禁用时不动作、`--test`/`--status` 行为 |
| `test_alert_flow.sh` | 造异常验证去抖（连续 3 次才推、第 4 次沉默）与恢复通知 |
| `hookrecv.py` | 本地 webhook 接收器，把收到的正文打出来验证推送真的发出去了 |
| `probe_mark.sh` | 实测 mark→接口映射、查看 uhttpd CGI 配置 |
| `make_stat_mock.js` | 生成可手算核对的 mock 数据（值等于序号，便于验分位数）到 `tests/statmock/` |
| `menu-argon.js` / `ui.js` / `luci.js` | 从真机抓回的 LuCI 前端源码副本，排查侧栏菜单渲染问题用 |
| `diag_curl.sh` / `diag_curl2.sh` | 诊断移动出口 HTTP 目标失败：区分「线路不通」和「源地址策略路由不对」 |
| `diag_qq.sh` | 定位 `rc=52`（服务器按 Host 头掐断连接，握手其实已完成） |
| `stability.sh` | 连跑 5 轮采集统计各目标成败率 |
| `fix_names.sh` | 统一 history.log 里的目标名（改名后必须跑） |
| `test_lan_cidr.sh` | 内网网段匹配的单元测试：用 `/25` 和 `/16` 卡住「前缀匹配」这个坑 |
| `diag_connect.sh` / `diag_connect2.sh` / `diag_connect3.sh` | 复现 `time_connect` 为 0 的路径：区分 rc=7（真失败）与 rc=52/56（不填 `-w`） |
| `diag_loss.sh` | 统计 history.log 里第二字段的取值分布，看 `0,1` 脏数据落在哪些目标上 |
| `clean_zero.sh` | 清洗历史 `=0,1` 脏数据为 `=FAIL,100`（改前自动备份 `history.log.bak-zero`） |
| `verify_zero.sh` | 采集后立刻检查最新行里还有没有 `=0,1` |
| `lossdist.sh` / `lossdist2.sh` | 早期定位用：按目标拆开看第二字段分布与原始行 |
| `diag_ts.sh` | Tailscale 诊断：prefs（`AdvertiseRoutes`/`CorpDNS`）、status、`ip rule`、iptables 的 `ts-*` 链、各接口地址、uhttpd 监听 |
