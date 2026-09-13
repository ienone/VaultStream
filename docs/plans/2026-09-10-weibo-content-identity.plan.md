# 微博内容身份统一

状态：当前工作区身份统一范围已实现并验证，详见同名 process。

真实同源 ID 5331437486081232 / RdbPCpw0o 解析正文相同，但 canonical URL 与 platform ID 不同；create_share 按 canonical 去重，存在重复收藏路径。

依据微博 MID/BID 分段 Base62 规则（参考 https://github.com/node-modules/weibo-mid），在适配器 URL 净化阶段统一为数字详情 ID，解析也使用同一数字 ID。主页保持原有身份，不增加网络查询。真实上游返回同时提供数字 id 与 mblogid，可交叉核验。

验证：真实已观测 ID 对、标准用户/博文与两种 detail 路径归一；真实 SQLite create_share 复用内容并保存不同来源；原样本实际解析复验。当前用户库未导入微博样本，不批量迁移或删除其他内容。
