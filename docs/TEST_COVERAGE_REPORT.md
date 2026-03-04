# 📊 VaultStream 后端测试覆盖率诊断报告

## 1. 整体概况
*   **总代码量**: 10,541 行
*   **已覆盖**: 3,745 行
*   **未覆盖**: 6,796 行
*   **整体覆盖率**: **36%** 
*   **健康度评估**: 处于初期阶段。数据模型和基础 API 已有一定覆盖，但核心业务逻辑（解析、定时任务、Bot 交互）处于“裸奔”或“跳过”状态。

## 2. 模块覆盖率雷达图 (按现状分组)

| 模块类别 | 涉及目录 | 覆盖率 | 现状诊断 |
| :--- | :--- | :--- | :--- |
| **🟢 数据契约 (高)** | `app/models/`, `app/schemas/` | **~100%** | 定义良好的 SQLAlchemy 和 Pydantic 模型，由于无需复杂逻辑，在其他测试初始化时被自然覆盖。 |
| **🟡 核心基建 (中)** | `app/core/`, `app/repositories/` | **50% - 80%** | 数据库操作、配置加载有基础测试。但队列 (`queue_adapter.py` 42%) 和事件总线 (`events.py` 40%) 的异常分支未测。 |
| **🟡 API 路由 (中下)** | `app/routers/` | **30% - 60%** | 大部分端点的“正常请求”已测，但对于权限校验失败、外部依赖超时等异常处理分支缺乏覆盖。 |
| **🔴 核心业务调度 (低)** | `app/services/`, `app/tasks/` | **15% - 30%** | **重灾区**。这是系统的“大脑”。例如 `distribution_worker.py` (17%) 和 `parsing.py` (17%)，一旦出错会导致系统停转。 |
| **🔴 解析与爬虫 (极低)** | `app/adapters/` 及其子目录 | **19%** | **虚假繁荣**。虽然写了测试，但由于强依赖真实的 Cookie 和网络，大部分用例在本地和 CI 中被 `Skipped` (跳过)。 |
| **🔴 机器人交互 (空白)** | `app/bot/` | **0%** | 完全没有测试。Telegram Bot 的指令解析、回调处理（`commands.py`, `callbacks.py`）存在极大的不可控风险。 |

---

# 🚀 提升有效覆盖率：优先级与实施路径

为了实现投入产出比（ROI）的最大化，建议将后续的测试补充工作分为三个优先级（P0, P1, P2）推进：

### 🚨 P0 级别：修复破窗与阻断点 (即刻执行)
*目标：让现有的测试真正跑起来，消除因基础设施导致的低覆盖率。*

1.  **修复失败的测试用例**：
    *   **动作**：修复 `test_distribution_phase2.py` 中的 `MissingGreenlet` 报错。在异步方法中访问未懒加载的 SQLAlchemy 关联属性会导致此错误，需在数据库查询时引入 `selectinload`。
2.  **解绑 Adapters/Parsers 的网络依赖 (Mocking)**：
    *   **动作**：对于 B站、微博、推特等解析器，**停止真实的网络请求**。收集真实 API 返回的 JSON 样本和 HTML 源码存入 `tests/data/` 目录。
    *   **效果**：使用 `httpx-mock` 拦截请求并返回本地样本。这能让那 10 个被跳过的 Adapter 测试瞬间变为 Passed，并能让覆盖率立刻飙升 10% 左右。

### ⚡ P1 级别：保卫系统的“心脏” (本周/迭代核心任务)
*目标：确保内容解析、入库、分发的核心主链路绝对可靠。*

1.  **覆盖 Tasks & Services (后台任务)**：
    *   **焦点**：`app/tasks/parsing.py` 和 `app/tasks/distribution_worker.py`。
    *   **动作**：测试任务的重试机制、失败后的状态流转。模拟下游服务（如 Telegram API）返回 500 错误，确保系统能正确将其标记为重试或失败，而不是崩溃。
2.  **覆盖 `content_agent.py` 与 AI 摘要**：
    *   **焦点**：`app/adapters/utils/content_agent.py` 目前仅 10% 覆盖率。
    *   **动作**：Mock 大模型的 API 响应，测试它在面对超长文本截断、AI 幻觉返回错误格式时的健壮性。

### 🛠️ P2 级别：补齐边界层与外围设施 (长期维护)
*目标：提升代码健壮性，防止边缘 Bug 泄漏到生产环境。*

1.  **攻克 Telegram Bot 交互 (`app/bot/`)**：
    *   **动作**：无需真实启动 Bot 即可测试。通过构造标准的 Telegram Update JSON 对象，直接传入 `bot/main.py` 的路由分发函数，断言系统是否返回了正确的回复消息。
2.  **API 的异常路径测试 (Negative Testing)**：
    *   **动作**：对于 `app/routers/` 下的接口，故意传入格式错误的 payload、不存在的 ID 或越权访问，断言接口返回标准的 `400` 或 `404` 错误代码，而非抛出 `500` 内部服务器错误。

---

# 💡 最佳实践建议（落地指南）

在接下来写测试代码时，可以参考以下模式：

**1. 善用参数化测试 (`@pytest.mark.parametrize`)**
不要为 B站视频解析、专栏解析写无数个长长的函数。写一个通用的解析器测试函数，通过参数化传入不同的本地 JSON 样本和预期的输出结果。

**2. 建立标准的 Mock Fixture**
在 `tests/conftest.py` 中建立全局可用的“假环境”。比如：
```python
@pytest.fixture
def mock_httpx_client(httpx_mock):
    # 所有测试默认拦截真实网络，防止意外泄漏真实的 API Token
    httpx_mock.add_response(url="https://api.bilibili.com/x/web-interface/view", json={"code": 0, "data": {...}})
```
