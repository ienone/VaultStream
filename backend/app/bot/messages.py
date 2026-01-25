"""
Bot 消息文本模块

存储所有 Bot 使用的静态文本和模板
"""

HELP_TEXT_START = (
    "欢迎使用 <b>VaultStream Bot</b>\n\n"
    "<b>可用命令</b>:\n"
    "/get - 随机获取一条待推送的内容\n"
    "/get_tag &lt;标签&gt; - 获取指定标签的内容\n"
    "/get_twitter - 获取 Twitter 推文\n"
    "/get_bilibili - 获取 B站内容\n"
    "/list_tags - 查看所有可用标签\n"
    "/status - 查看系统状态\n"
    "/help - 显示详细帮助\n\n"
    "<b>示例</b>:\n"
    "<code>/get_tag 技术</code>\n"
    "<code>/get_twitter</code>\n"
)

HELP_TEXT_FULL = (
    "<b>VaultStream Bot 帮助</b>\n\n"
    
    "<b>基本命令</b>\n"
    "/get - 随机获取一条待推送的内容\n"
    "/status - 查看系统运行状态和队列情况\n\n"
    
    "<b>按标签筛选</b>\n"
    "/get_tag &lt;标签&gt; - 获取带指定标签的内容\n"
    "/list_tags - 查看所有可用标签及其数量\n"
    "示例: <code>/get_tag 技术</code>\n\n"
    
    "<b>按平台筛选</b>\n"
    "/get_twitter - 获取 Twitter/X 平台的推文\n"
    "/get_bilibili - 获取 B站平台的内容\n\n"
    
    "<b>使用说明</b>\n"
    "• 所有命令都会自动标记为已推送\n"
    "• 可以组合使用标签和平台筛选\n"
    "• 内容按创建时间顺序获取\n"
)

MSG_NO_PERMISSION = "您没有权限使用此Bot"
MSG_BLACKLISTED = "您已被禁止使用此Bot"
MSG_ADMIN_ONLY = "此命令仅限管理员使用"
MSG_UNKNOWN_ERROR = "发生未知错误"
MSG_API_ERROR = "无法连接到后端服务"
MSG_TIMEOUT = "请求超时，请稍后重试"
