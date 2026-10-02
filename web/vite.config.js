import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// 产物要挂到路由器的 /lm/app/ 下，且外层是 LuCI 的 iframe，
// 所以资源引用一律走相对路径（base './'），绝对路径会打到 LuCI 的根上去。
export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    // 路由器是 mips，没有本地构建，构建只在本机做；这里只关心传输体积
    chunkSizeWarningLimit: 2000,
    rollupOptions: {
      output: {
        manualChunks: {
          // React 和 antd 体量大、改动少，单独切出来让浏览器能分开缓存。
          // 图表用 Chart.js，没引 @ant-design/plots（它的 G2 换不动那套断线/丢包虚线逻辑）。
          react: ['react', 'react-dom'],
          antd: ['antd', '@ant-design/pro-components'],
        },
      },
    },
  },
});
