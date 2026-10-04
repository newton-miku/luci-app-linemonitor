'use strict';
'require view';
'require ui';

return view.extend({
	render: function () {
		// 侧栏菜单树在客户端被缓存进 sessionStorage（luci-session-store），
		// 硬刷新清不掉。首次安装/升级后浏览器可能仍持有不含本应用的旧菜单，
		// 导致「服务 → 线路监测」不出现。这里做一次性自愈：
		// 若树里没有 linemon 就清缓存并重载，标记位防止循环。
		var flag = 'lm_menu_synced';

		Promise.resolve(ui.menu.load()).then(function (menu) {
			try {
				if (sessionStorage.getItem(flag))
					return;

				var services = menu.children.admin.children.services;
				var kids = ui.menu.getChildren(services);

				for (var i = 0; i < kids.length; i++)
					if (kids[i].name == 'linemon')
						return;

				sessionStorage.setItem(flag, '1');
				ui.menu.flushCache();
				ui.menu.menu = null;
				window.location.reload();
			}
			catch (e) { /* 树结构异常时静默跳过，不影响看板 */ }
		});

		return E('iframe', {
			// uhttpd 只给 ETag/Last-Modified，不发 Cache-Control。父页面硬刷新时
			// 浏览器常常直接复用 iframe 里的旧文档，看不到刚部署的新版。带上版本串，
			// URL 一变就会重新拉取。改了 /www/lm/line.html 记得把这个值一起改。
			src: '/lm/app/index.html?v=20261004a',
			style: 'width: 100%; min-height: 720px; height: calc(100vh - 190px); ' +
			       'border: none; border-radius: 3px; resize: vertical; background: #fff;'
		});
	},
	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
