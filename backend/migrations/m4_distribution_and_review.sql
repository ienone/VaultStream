-- M4: 分发规则与审批流迁移脚本
-- 添加审批流字段到 contents 表

-- 1. 添加审批状态字段
ALTER TABLE contents ADD COLUMN review_status TEXT DEFAULT 'pending';
ALTER TABLE contents ADD COLUMN reviewed_at TIMESTAMP;
ALTER TABLE contents ADD COLUMN reviewed_by TEXT;
ALTER TABLE contents ADD COLUMN review_note TEXT;

-- 2. 创建索引
CREATE INDEX IF NOT EXISTS ix_contents_review_status ON contents(review_status);

-- 3. 扩展 pushed_records 表
-- 先删除旧的唯一约束（如果存在）
-- DROP INDEX IF EXISTS uq_pushed_records_content_target;

-- 添加新字段
ALTER TABLE pushed_records ADD COLUMN target_id TEXT;
ALTER TABLE pushed_records ADD COLUMN push_status TEXT DEFAULT 'success';
ALTER TABLE pushed_records ADD COLUMN error_message TEXT;

-- 更新已有数据：将 target_platform 映射到 target_id
UPDATE pushed_records SET target_id = target_platform WHERE target_id IS NULL;

-- 创建唯一约束和索引
CREATE UNIQUE INDEX IF NOT EXISTS uq_pushed_records_content_target 
    ON pushed_records(content_id, target_id);
CREATE INDEX IF NOT EXISTS ix_pushed_records_target_id ON pushed_records(target_id);

-- 4. 创建分发规则表
CREATE TABLE IF NOT EXISTS distribution_rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    match_conditions TEXT NOT NULL,  -- JSON
    targets TEXT NOT NULL,  -- JSON
    enabled BOOLEAN DEFAULT 1,
    priority INTEGER DEFAULT 0,
    nsfw_policy TEXT DEFAULT 'block',
    approval_required BOOLEAN DEFAULT 0,
    auto_approve_conditions TEXT,  -- JSON
    rate_limit INTEGER,
    time_window INTEGER,
    template_id TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_distribution_rules_enabled ON distribution_rules(enabled);
CREATE INDEX IF NOT EXISTS ix_distribution_rules_priority ON distribution_rules(priority);

-- 5. 为已有内容设置默认审批状态
-- 已抓取或已归档的内容自动批准
UPDATE contents 
SET review_status = 'auto_approved', reviewed_at = CURRENT_TIMESTAMP
WHERE status IN ('pulled', 'archived') AND review_status = 'pending';

-- 提交说明：
-- M4 迁移完成后，所有新入库内容默认为 pending 状态
-- 需要通过审批 API 或自动审批规则批准后才能分发
