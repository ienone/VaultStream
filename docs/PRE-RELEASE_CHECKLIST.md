# VaultStream 开源发布准备清单备忘录

## 1. 部署与开源准备
- **Web 部署**: 已有 Nginx 网关配置，后端 FastAPI 提供 API，前端 Flutter 构建 Web 产物并由 Nginx 代理或直接静态托管。
- **APK 生成 (GitHub Release)**: 
  - 需要配置 Android 签名 (Keystore)。
  - 需要确保 `applicationId` (如 `com.ienone.vaultstream`) 已经设置好。
  - 需要在 GitHub Actions 中配置自动构建和签名（如果使用 CI），或者本地构建 `flutter build apk --release` 后手动上传。
- **开源仓库检查**:
  - 确保脱敏，防止 `vaultstream.db`、`.env`、真实 Token/Cookie 泄漏。
  - 检查 `.gitignore` 是否完备。
  - **复审核查结果 (2026-02-22)**: 
    - 根目录 `.gitignore` 非常规范，成功阻断了所有可能导致敏感信息泄露的文件和目录（如 `.env`, `data/`, `logs/`）。
    - 经过硬编码 Secret 扫描（SESSDATA, bili_jct, bot_token, access_token, api_key 等），未发现泄露真实的敏感信息。目前代码库处于**安全脱敏状态**。
    - **改进建议**: 在 `.gitignore` 中补充 `*.jks` 和 `*.keystore`，防止后续安卓签名文件被意外提交。

## 2. 鉴权逻辑的显式展现
- **现状**: 前端通过设置页手动输入 Server URL 和 API Token，不够直观。
- **目标**: 引入“引导页 / 登录页 (Onboarding / Login)”。当本地无有效配置时，强制要求输入并验证，成功后再进入主面板。
- **实施结果 (2026-02-22)**:
  - **同步初始化配置加载**: 重构了 `main.dart` 中的 `SharedPreferences` 初始化逻辑。改为应用启动前（在 `WidgetsFlutterBinding.ensureInitialized()` 后）通过异步转同步方式读取，实现配置在启动瞬间立即可用，避免因异步加载引起的路由闪烁。
  - **GoRouter 全局重定向拦截**: 在 `app_router.dart` 中新增全局 `redirect` 逻辑。一旦检测到缺失有效的 `baseUrl` 或 `apiToken`，且非访问登录页的情况下，将无缝重定向至 `/login` 路由。
  - **Material 3 Expressive 引导页**: 新增了 `login_page.dart`。该页在视觉上引入了带有阴影效果（Elevation 4）及圆角边框的 Card 悬浮设计，采用了具有 M3 表达力（Expressive）的强调色填充按钮（`FilledButton`），并配有表单即时验证提示及加载中动画。
  - **严密的鉴权连通性测试**: 将此前不涉及授权检查的白名单 `/health` 接口测试，替换为对后端 `/api/v1/dashboard/stats` 接口的校验。确保只有在 `X-API-Token` 正确（返回 200）的情况下才会放行，401 会被正常拒之门外，保障了本地配置下发时的真实有效性。
  - **注销闭环**: 修改了全局设置页中的登出逻辑。如今在清空本地配置（`clearAuth()`）后，通过 `context.go('/login')` 直接触发路由状态更新并将用户踢回至显式的引导验证页。

## 3. 前后端设置不对齐与布局美化
- **现状**: `settings_page.dart` 揉杂了本地连接、平台授权、AI 配置，缺乏分类，与后端复杂的配置（分发规则、推送配置）割裂。
- **目标**: 
  - **分类重构**: 左侧导航栏或 Tab 页（连接设置、平台账号、推送配置、偏好系统）。
  - **UI 统一**: 使用 Material 3 组件 (ListTile, Card, SettingsList) 统一包装。
- **实施结果 (2026-02-22)**:
  - **响应式布局重构**: 对 `settings_page.dart` 进行了彻底重构，引入了 `LayoutBuilder`，为宽屏设备提供 `NavigationRail`（左侧导航栏）布局，为窄屏设备提供 `TabBar` 布局。
  - **配置解耦与分类**: 将原先单一的千行代码拆分为 4 个高度聚焦的模块化 Tab 页面，存放在 `features/settings/presentation/tabs/` 下：
    - `ConnectionTab` (连接与账号): 集中管理 API Token、服务器地址、网络代理及各平台 (B站、微博、X、小红书) 的 Cookie 授权。
    - `AutomationTab` (AI 发现): 专注处理 AI Agent 自动发现的开关、检索主题及解析 Prompt 配置。
    - `PushTab` (推送与通知): 分流了客户端通知首选项及多端 Bot 路由绑定的入口。
    - `SystemTab` (外观与系统): 掌管主题模式 (ThemeMode)、缓存清理、备份系统和应用开源信息。
  - **Material 3 Expressive 组件化**: 抽取了 `SettingTile`、`ExpandableSettingTile`、`SettingGroup` 及 `SectionHeader`。采用了更具表现力的大圆角 (`Radius 28` / `Radius 20`) 以及底色高亮（`surfaceContainerLow` / `primaryContainer`）替代了传统的平铺列表，使得整体视觉在跨端体验下更加自然美观。
  - **前后端配置管理统一与对齐**: 
    - 移除了前端中不准确或尚未实现的配置项（如代理配置、备份恢复、通知偏好）。
    - 针对后端：修改了 `settings_service.py`，使 `list_settings_values` 接口不仅返回 SQLite 数据库中的动态配置，还能将 `.env` 环境变量中静态配置的平台 Cookie (如知乎、B站、小红书、微博) 虚拟化为设置项合并返回。
    - 彻底修复了 `.env` 中明明已配置了访问凭证，但前端界面因未查到数据库记录而错误显示为“尚未配置”的 Bug。同时将不需要凭证的平台（如 Twitter/X）从前端配置面板中移除，加入了对知乎凭证的显式状态支持。
  - **全栈配置动态化 (Phase 2)**:
    - **后端核心升级**: 改造 `settings_service` 和 `llm_factory`，实现了对 `.env` 环境变量的数据库级 Fallback 机制。这意味着原先写死在环境变量中的 LLM 密钥、Proxy 配置、Telegram 权限等，现在都支持在前端界面上即时覆盖修改，无需重启服务。
    - **前端高级配置落地**: 
      - **AutomationTab**: 新增了 Text/Vision LLM 的完整配置面板 (Base URL / API Key / Model)，支持随时切换模型引擎。
      - **ConnectionTab**: 补全了“网络代理配置”和“B站高级配置 (JCT/BuVid3)”，解决了国内网络环境下的痛点。
      - **PushTab**: 开放了 Telegram Bot 的权限控制 (Admin/Whitelist/Blacklist)，赋予用户即时的风控能力。
      - **SystemTab**: 引入了“存储与归档策略”控制，用户可动态开关 WebP 压缩、调节画质质量及单帖图片上限。
  - **界面与体验优化 (2026-02-22)**:
    - **B站配置分级**: 响应用户需求，将 B站从主凭证列表中移除（强调其免登录可用性），并将其 SESSDATA / CSRF / BuVid3 等参数下沉至“高级配置”区。
    - **配置可视化增强**: 为 API Token、LLM Key、Proxy 等敏感或关键配置项增加了“当前状态副标题”显示。密钥类字段默认采用掩码 (Masking) 展示（如 `sk-****1234`），让配置状态一目了然。

## 4. 文档 FLAG 更新 (Roadmap)
- **目标**: 在 `README.md` 等文档中补充未来路线图 (Roadmap)，吸引开发者。
- **实施结果 (2026-02-22)**:
  - 已在 `README.md` 中新增 `🗺️ 未来路线图 (Roadmap)` 章节，涵盖了 AI RAG/Agent、收藏夹自动同步、RSS 集成以及 Telegram 群组深度集成等四大旗舰规划。

## 5. 后端启动脚本与打包分发
- **目标**: 修复 `start.sh` 路径 Bug，提供 Docker 部署支持。
- **实施结果 (2026-02-22)**:
  - **修复启动脚本**: 修改了 `backend/start.sh`，使其能自动检测 `.venv` 或 `vaultstream_env` 目录，兼容 `install.sh` 的不同安装模式。
  - **Docker 支持**: 
    - 创建了 `backend/Dockerfile`，基于 `python:3.11-slim`，内置了 `ffmpeg` 等必要依赖。
    - 提供了标准的 `backend/docker-compose.yml`，支持一键启动 (`docker-compose up -d`)，并挂载了数据、日志和配置文件，实现了开箱即用。
