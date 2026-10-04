import { useMemo } from 'react';
import { ProCard, StatisticCard } from '@ant-design/pro-components';
import BarChart from '../components/BarChart.jsx';
import Spark from '../components/Spark.jsx';
import StatTable from '../components/StatTable.jsx';
import { avgOf, lastValue, valColor, statForKey, fmtNum, fmtFull, fmtRate, fmtClock } from '../stats.js';
import { wantsV4, wantsV6, targetsFor } from '../api.js';

const { Statistic } = StatisticCard;

// 实时速率条：每个接口一行，左边接口名，右边 ↓下行 / ↑上行。
// 速率是 lm_rate.sh 每 INTERVAL_RATE 秒采的字节差，前端 2 秒拉一次 CGI。
function RateRow({ r }) {
  return (
    <div className="lm-rate-row">
      <span className="lm-rate-if">{r.label || r.if}</span>
      <span className="lm-rate-val lm-rate-rx">↓ {fmtRate(r.rx)}</span>
      <span className="lm-rate-val lm-rate-tx">↑ {fmtRate(r.tx)}</span>
    </div>
  );
}

export default function Overview({ cfg, hist, rate, range, onOpenExit }) {
  const exits = cfg.exits || [];

  const winMs = range ? range.max - range.min : 0;
  const endTs = range ? range.max / 1000 : (hist.length ? hist[hist.length - 1].ts : 0);

  // 每个出口的 v4/v6 平均延迟。v6 这边之前写的是「可达/不可达」，
  // 但那个词没信息量——有延迟数字就直接显示数字。
  const cards = useMemo(() => {
    const out = [];
    for (const e of exits) {
      const lbl = e.label || e.if;
      // 出口可声明只测某几组目标（外网=公网 DNS、组网=对端子网），过滤后再算均值
      const t4 = targetsFor(e, cfg.targets_v4);
      const t6 = targetsFor(e, cfg.targets_v6);
      if (wantsV4(e)) {
        const vals = t4.map((t) => lastValue(hist, e.if + '|' + t.name)).filter((v) => v !== null);
        const a = avgOf(vals);
        const fail = t4.some((t) => {
          const s = hist.length ? hist[hist.length - 1].series[e.if + '|' + t.name] : null;
          return s && (s.value === null || s.value === undefined);
        });
        out.push({
          key: 'v4-' + e.if, label: lbl + ' 平均延迟', value: a, tab: 'ex:' + e.if,
          prefix: e.if, targets: t4,
          detail: fail ? '最近一次存在失败目标' : '全部目标正常',
        });
      }
      if (wantsV6(e)) {
        const vals = t6.map((t) => lastValue(hist, 'v6-' + e.if + '|' + t.name)).filter((v) => v !== null);
        const a = avgOf(vals);
        const fail = t6.some((t) => {
          const s = hist.length ? hist[hist.length - 1].series['v6-' + e.if + '|' + t.name] : null;
          return s && (s.value === null || s.value === undefined);
        });
        out.push({
          key: 'v6-' + e.if, label: 'IPv6 ' + lbl + ' 平均延迟', value: a, tab: 'ex:' + e.if,
          prefix: 'v6-' + e.if, targets: t6,
          detail: fail ? '最近一次存在丢包/失败目标' : '全部目标正常',
        });
      }
    }
    return out;
  }, [exits, cfg.targets_v4, cfg.targets_v6, hist]);

  // 统计表按「出口 × 协议」分块，v4 与 v6 不再混在一张表里
  const groups = useMemo(() => {
    const g = [];
    for (const e of exits) {
      const lbl = e.label || e.if;
      if (wantsV4(e)) g.push({ label: `${lbl} (IPv4)`, prefix: e.if, targets: targetsFor(e, cfg.targets_v4) });
      if (wantsV6(e)) g.push({ label: `${lbl} (IPv6)`, prefix: 'v6-' + e.if, targets: targetsFor(e, cfg.targets_v6) });
    }
    return g;
  }, [exits, cfg.targets_v4, cfg.targets_v6]);

  const v4Exits = exits.filter(wantsV4);
  const sampleN = hist.length;
  const rates = (rate && rate.rates) || [];
  const rateTs = rate && rate.ts ? rate.ts : 0;

  return (
    <>
      {rates.length ? (
        <ProCard
          title="实时速率"
          bordered
          style={{ marginBottom: 16 }}
          extra={
            <span className="lm-updated">
              {rateTs ? '更新 ' + fmtClock(rateTs) : '等待首次采样'}
            </span>
          }
        >
          <div className="lm-rate-grid">
            {rates.map((r) => (
              <RateRow key={r.if} r={r} />
            ))}
          </div>
          <div className="lm-note">
            读 /proc/net/dev 的累计字节数做差；数字是最近一个采样间隔的平均值，
            不是瞬时值。空闲时的几 KB/s 属于协议开销与后台同步。
          </div>
        </ProCard>
      ) : null}

      <ProCard gutter={16} wrap ghost style={{ marginBottom: 16 }}>
        {cards.map((c) => (
          <ProCard key={c.key} colSpan={4} style={{ minWidth: 200 }}>
            <StatisticCard
              onClick={() => onOpenExit(c.tab)}
              style={{ cursor: 'pointer' }}
              statistic={{
                title: c.label,
                value: c.value === null ? '—' : Math.round(c.value),
                suffix: c.value === null ? '' : 'ms',
                valueStyle: { color: valColor(c.value), fontSize: 24, fontWeight: 600 },
                description: c.detail,
              }}
              chart={<Spark hist={hist} prefix={c.prefix} targets={c.targets} />}
              chartPlacement="bottom"
            />
          </ProCard>
        ))}
        <ProCard colSpan={4} style={{ minWidth: 200 }}>
          <StatisticCard
            statistic={{
              title: '采集点数',
              value: sampleN,
              valueStyle: { fontSize: 24, fontWeight: 600 },
              description: hist.length
                ? `${fmtFull(hist[0].ts)} ~ ${fmtFull(hist[hist.length - 1].ts)}`
                : '暂无数据',
            }}
          />
        </ProCard>
      </ProCard>

      <ProCard title="各目标延迟对比（最新一次采集，ms）" bordered style={{ marginBottom: 16 }}>
        {v4Exits.length ? (
          <BarChart hist={hist} exits={v4Exits} targets={cfg.targets_v4 || []} />
        ) : (
          <div style={{ color: 'rgba(255,255,255,.45)' }}>没有配置 IPv4 目标的出口</div>
        )}
        <div className="lm-note">
          ICMP 类目标若 100% 丢包多为 [DNS/ICMP 受限]，非线路故障。
        </div>
      </ProCard>

      <ProCard
        title="统计 · 每个监测目标"
        bordered
        extra={
          <span className="lm-updated">
            窗口 {winMs ? Math.round(winMs / 60000) + ' 分钟' : '全部'}
          </span>
        }
      >
        <StatTable
          hist={hist}
          groups={groups}
          winMs={winMs}
          endTs={endTs}
          th={cfg.th || {}}
          showGroup
        />
        <div className="lm-note">
          〔样本〕是窗口内的成功次数 / 总采集次数。丢包率取每次采样的丢包百分比的平均；
          平均与分位数只统计成功样本，波动 σ 是它们的标准差。ICMP 类目标若被运营商限制会显示成高丢包，
          那是限制不是线路故障。
        </div>
      </ProCard>
    </>
  );
}
