// 统计表：总览页和出口页共用。
// groups 每一项是一「块」（一个出口的一个协议），块内每个目标一行。
// 目标现在是对象 {name, grp, kind}（lm_config_json.sh 导出的），
// 名字带分组前缀显示（公网/内网），看曲线键时只用 name。
import { Table } from 'antd';
import { statForKey, lossTxt, lossCls, thCls, fmtNum } from '../stats.js';

export default function StatTable({ hist, groups, winMs, endTs, th, showGroup }) {
  const rows = [];
  const spans = {};

  groups.forEach((g, gi) => {
    const groupRows = g.targets.map((t) => {
      const key = g.prefix + '|' + t.name;
      const s = statForKey(hist, key, winMs, endTs);
      return {
        group: g.label,
        gid: gi,
        target: (t.grp ? t.grp + '/' : '') + t.name,
        s,
      };
    });
    spans[gi] = groupRows.length;
    rows.push(...groupRows);
  });

  const cols = [];
  if (showGroup) {
    cols.push({
      title: '线路',
      dataIndex: 'group',
      key: 'group',
      width: 110,
      className: 'lm-group',
      // antd v5 里合并单元格得用 onCell 返回 rowSpan，不能再靠 render 返回 props
      onCell: (row) => ({ rowSpan: row.__first ? spans[row.gid] : 0 }),
    });
  }
  cols.push(
    { title: '目标', dataIndex: 'target', key: 'target', width: 120 },
    { title: '样本(有效/总)', key: 'n', width: 130, align: 'right',
      render: (_, r) => `${r.s.ok} / ${r.s.total}` },
    { title: '丢包率', key: 'loss', width: 90, align: 'right',
      render: (_, r) => <span className={'lm-num ' + lossCls(r.s.loss)}>{lossTxt(r.s.loss)}</span> },
    { title: '平均', key: 'avg', width: 80, align: 'right', render: (_, r) => fmtNum(r.s.avg) },
    { title: 'p50', key: 'p50', width: 80, align: 'right', render: (_, r) => fmtNum(r.s.p50) },
    { title: 'p95', key: 'p95', width: 80, align: 'right', render: (_, r) => fmtNum(r.s.p95) },
    { title: 'p99', key: 'p99', width: 80, align: 'right', render: (_, r) => fmtNum(r.s.p99) },
    { title: '最大', key: 'max', width: 90, align: 'right',
      render: (_, r) => <span className={'lm-num ' + thCls(r.s.max, th.maxWarn, th.maxBad)}>{fmtNum(r.s.max, 0)}</span> },
    { title: '波动σ', key: 'sd', width: 90, align: 'right',
      render: (_, r) => <span className={'lm-num ' + thCls(r.s.sd, th.sdWarn, th.sdBad)}>{fmtNum(r.s.sd)}</span> },
  );

  const data = rows.map((r, i) => {
    const first = i === 0 || rows[i - 1].gid !== r.gid;
    return { ...r, key: r.gid + '-' + r.target, __first: first };
  });

  return (
    <Table
      columns={cols}
      dataSource={data}
      pagination={false}
      size="middle"
      tableLayout="fixed"
      scroll={{ x: 'max-content' }}
    />
  );
}
