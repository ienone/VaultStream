# VaultStream 前后端数据库重构与契约对齐方案

## 1. 核心设计哲学

本方案旨在解决 "平台特有数据泄漏" 问题，将架构从 "业务驱动" 转变为 "组件驱动"。

*   **三层契约架构：**
    1.  **标准化核心层 (Standardized Core):** 物理列。存储所有平台共有的元数据（标题、作者、封面、清洗后的描述）。
    2.  **结构化扩展层 (Structured Extensions):** JSONB 列。存储聚合后的 **UI 组件数据**（如关联上下文、富媒体块），而非平台原始字段。
    3.  **存档存储层 (Archive Storage):** JSONB 列。存储原始数据，仅供后端审计与二次解析，**API 严禁返回**。

*   **前端零平台逻辑：** 
    前端不再包含 `if (isZhihu)` 或读取 `raw_metadata` 的逻辑。UI 只根据数据呈现的 "模式"（UI Patterns）进行渲染。

---

## 2. 后端：数据库模型重构 (SQLAlchemy)

### 2.1 新 `Content` 模型结构

```python
class Content(Base):
    __tablename__ = "contents"

    # --- 1. 标准化核心字段 (API 必须返回) ---
    id = Column(Integer, primary_key=True, index=True)
    platform = Column(String(50), nullable=False, index=True)
    canonical_url = Column(Text, unique=True, index=True)
    
    # 基础展示
    title = Column(Text)
    description = Column(Text) # 已清洗的富文本/Markdown (禁止包含 HTML)
    cover_url = Column(Text)
    cover_color = Column(String(20)) # 存档时预计算的主色调 (Hex)
    
    # 统一指标 (Adapter 负责映射)
    # 强制要求 Adapter 将 B站硬币、微博转发等映射到此处
    view_count = Column(Integer, default=0)
    like_count = Column(Integer, default=0)
    comment_count = Column(Integer, default=0)
    collect_count = Column(Integer, default=0)
    share_count = Column(Integer, default=0)

    # 作者信息
    author_name = Column(String(200))
    author_avatar_url = Column(Text)
    author_url = Column(Text)
    author_id = Column(String(100))

    # --- 2. 结构化扩展组件 (API 必须返回，取代泄漏字段) ---
    
    # [Context Slot] 关联上下文
    # 取代 associated_question / referenced_tweet
    # 结构：{"type": "parent/reference", "title": "...", "url": "...", "cover": "..."}
    context_data = Column(JSON, nullable=True)

    # [Rich Payload] 富媒体/交互组件块
    # 取代 top_answers / video_pages / thread_items
    # 结构：{"blocks": [{"type": "sub_item/poll/media_grid", "data": {...}}]}
    rich_payload = Column(JSON, nullable=True)

    # --- 3. 存档与内部字段 (API 严禁返回) ---
    
    # [Archive Blob] 原始元数据
    # 取代 raw_metadata，仅用于后端审计和重解析
    archive_metadata = Column(JSON) 
    
    # 软删除支持
    deleted_at = Column(DateTime, nullable=True)
    
    # 系统状态
    status = Column(String(50), default="unprocessed", index=True)
    layout_type = Column(String(50), index=True) # 后端计算的最终布局
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, onupdate=utcnow)
```

### 2.2 迁移方案 (SQLite 影子表法)

由于 SQLite 对 `DROP COLUMN` 支持有限，建议使用全量表重建方式：

1.  **备份：** `cp vaultstream.db vaultstream.db.bak`
2.  **创建新表：** 创建符合上述 Schema 的 `contents_new` 表。
3.  **数据清洗与迁移脚本 (Python):**
    *   遍历旧 `contents` 表。
    *   **提取 Context:** 将 `associated_question` 转换为 `context_data = {"type": "question", ...}`。
    *   **提取 Blocks:** 将 `top_answers` 转换为 `rich_payload = {"blocks": [{"type": "sub_item", ...}]}`。
    *   **归档:** 将 `raw_metadata` 移动到 `archive_metadata`。
    *   **映射:** 将 `extra_stats` 中的通用计数写入主表列。
    *   插入 `contents_new`。
4.  **切换表名：**
    *   `DROP TABLE contents;`
    *   `ALTER TABLE contents_new RENAME TO contents;`
5.  **重建索引。**

---

## 3. API 契约：数据脱敏与减负

在 `schemas.py` 中明确隔离存档数据，确保 API 响应极简。

```python
class ContentDetail(BaseModel):
    id: int
    platform: str
    # ... 基础字段 ...
    
    # 核心扩展
    context_data: Optional[Dict[str, Any]]
    rich_payload: Optional[Dict[str, Any]]
    
    # 统一计数
    like_count: int = 0
    view_count: int = 0
    
    # 禁止字段
    # archive_metadata: NEVER include this
    # raw_metadata: REMOVED
    
    class Config:
        from_attributes = True
```

---

## 4. 前端：从 "业务驱动" 向 "组件驱动" 转型

### 4.1 模型改动 (Dart/Freezed)

修改 `frontend/lib/features/collection/models/content.dart`：

```dart
@freezed
class ContentDetail with _$ContentDetail {
  const factory ContentDetail({
    required int id,
    // ... 
    
    // 移除 associated_question, top_answers, raw_metadata
    
    // 新增通用容器
    @JsonKey(name: 'context_data') Map<String, dynamic>? contextData,
    @JsonKey(name: 'rich_payload') Map<String, dynamic>? richPayload,
    
    // 使用标准化的主表计数
    @JsonKey(name: 'like_count') @Default(0) int likeCount,
    // ...
  }) = _ContentDetail;
}
```

### 4.2 UI 渲染改动 (Component Renderer)

前端建立一套基于 **UI Pattern** 的渲染器，而非 Platform 判断：

1.  **Context Renderer:** 
    *   检查 `content.contextData`。
    *   如果存在，渲染顶部关联卡片（无论是知乎问题、引用推文还是 B 站合集，UI 结构统一）。

2.  **Block Renderer:** 
    *   检查 `content.richPayload['blocks']`。
    *   遍历块列表：
        *   `type == 'sub_item'` -> 渲染子内容列表（原知乎精选回答）。
        *   `type == 'media_grid'` -> 渲染图片网格。
        *   `type == 'poll'` -> 渲染投票组件。

### 4.3 前端收益
1.  **代码量减少：** 移除大量 `if (platform == 'zhihu')` 分支。
2.  **扩展性增强：** 接入新平台（如 Reddit）时，前端无需修改代码，只要后端输出标准的 `context` 或 `blocks` 结构即可自动渲染。
3.  **性能提升：** 内存占用降低，JSON 解析速度提升。

---

## 5. 执行路线图

1.  **Backend:** 修改 `models.py` 定义新 Schema，修改 `schemas.py` 移除废弃字段。
2.  **Adapters:** 更新各平台 Adapter 的 `parse` 方法，实现数据清洗与结构化聚合。
3.  **Migration:** 编写并执行 Python 迁移脚本，完成数据洗牌。
4.  **Frontend:** 重新生成 Dart 模型，利用编译器报错定位并替换所有硬编码逻辑。
