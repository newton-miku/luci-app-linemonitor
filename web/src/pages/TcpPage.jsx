// 实时 TCP 流：数据来自 tcp_stream.sh 生成的 tcp.json，
// 结构是 {"ts": <秒级时间戳>, "streams": [{...}]}。
import { useMemo, useState } from 'react';
import { ProCard } from '@ant-design/pro-components';
import { Input, Select, Table, Tag } from 'antd';

const COLS = [
  { key: 'client', title: '设备', width: 140 },
  { key: 'sport', title: '源端口', width: 90, align: 'right' },
  // 目标和端口合成一列读起来才完整，端口单列没人看得懂
  { key: 'dst', title: '目标', width: 240 },
  { key: 'iface', title: '出口', width: 130 },
  { key: 'service', title: '服务', width: 110 },
  { key: 'state', title: '状态', width: 140 },
];

export default function TcpPage({ tcp }) {
  const [kw, setKw] = useState('');
  const [iface, setIface] = useState('');

  const rows = useMemo(() => (tcp && Array.isArray(tcp.streams) ? tcp.streams : []), [tcp]);

  const ifaces = useMemo(() => {
    const s = new Set();
    for (const r of rows) if (r.iface) s.add(r.iface);
    return [...s];
  }, [rows]);

  const data = useMemo(() => {
    const k = kw.trim();
    return rows
      .filter((r) => !iface || r.iface === iface)
      .filter((r) => !k || Object.values(r).some((v) => String(v).includes(k)))
      .map((r, i) => ({ ...r, key: i }));
  }, [rows, kw, iface]);

  const columns = COLS.map((c) => ({
    ...c,
    dataIndex: c.key,
    ellipsis: true,
    render: (v, r) => {
      if (c.key === 'dst') {
        if (!v) return '—';
        return `${v}:${r.dport || ''}`;
      }
      if (c.key === 'state' && v) {
        const up = String(v).toUpperCase().includes('ESTAB');
        const wait = String(v).toUpperCase().includes('TIME_WAIT');
        return <Tag color={up ? 'green' : wait ? 'default' : 'orange'}>{v}</Tag>;
      }
      if (c.key === 'iface' && v === '未知') return <Tag>未知</Tag>;
      return v === null || v === undefined || v === '' ? '—' : String(v);
    },
  }));

  return (
    <ProCard
      title={`实时 TCP 流（${data.length} 条）`}
      bordered
      extra={
        <div style={{ display: 'flex', gap: 8 }}>
          {ifaces.length > 1 ? (
            <Select
              size="small"
              style={{ width: 140 }}
              value={iface}
              onChange={setIface}
              options={[{ label: '全部出口', value: '' }, ...ifaces.map((f) => ({ label: f, value: f }))]}
            />
          ) : null}
          <Input
            size="small"
            style={{ width: 220 }}
            allowClear
            placeholder="设备IP / 目标过滤"
            value={kw}
            onChange={(e) => setKw(e.target.value)}
          />
        </div>
      }
    >
      <Table
        columns={columns}
        dataSource={data}
        size="small"
        pagination={data.length > 50 ? { pageSize: 50, size: 'small' } : false}
        scroll={{ x: 'max-content' }}
      />
      <div className="lm-note">
        数据经 conntrack 读取，只统计源自内网网段的流；同一条连接在两侧各出现一次属正常。
        时间戳 {tcp && tcp.ts ? new Date(tcp.ts * 1000).toLocaleString('zh-CN') : '—'}。
      </div>
    </ProCard>
  );
}
