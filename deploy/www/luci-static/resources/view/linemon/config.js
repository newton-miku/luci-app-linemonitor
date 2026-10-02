'use strict';
'require view';

return view.extend({
	render: function () {
		return E('iframe', {
			// 版本串用于绕开 iframe 的复用缓存，改了 /www/lm/config.html 记得一起改
			src: '/lm/config.html?v=20261002i',
			style: 'width: 100%; min-height: 720px; height: calc(100vh - 190px); ' +
			       'border: none; border-radius: 3px; resize: vertical; background: #fff;'
		});
	},
	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
