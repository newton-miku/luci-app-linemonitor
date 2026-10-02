import React from 'react';
import ReactDOM from 'react-dom/client';
import { ConfigProvider, theme } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import 'dayjs/locale/zh-cn';
import dayjs from 'dayjs';
import App from './App.jsx';
import './index.css';

dayjs.locale('zh-cn');

// 跟 LuCI 的 Argon 深色主题对齐：整页 #000 底、卡片 #141414、主色用 antd v5 的 blue-6。
// algorithm 用 darkAlgorithm，token 只覆盖底色和圆角，其余全交给官方默认值——
// 这样观感就是 Pro 在线 demo 那一套，不是自己拼的。
ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <ConfigProvider
      locale={zhCN}
      theme={{
        algorithm: theme.darkAlgorithm,
        token: {
          colorPrimary: '#1668dc',
          colorBgLayout: '#000',
          colorBgContainer: '#141414',
          borderRadius: 8,
          fontFamily:
            "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial," +
            "'Noto Sans','PingFang SC','Microsoft YaHei',sans-serif",
        },
        components: {
          Card: { headerHeight: 56 },
          Table: { cellPaddingBlock: 12 },
        },
      }}
    >
      <App />
    </ConfigProvider>
  </React.StrictMode>
);
