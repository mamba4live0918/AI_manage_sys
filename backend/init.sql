-- 阶段一：数据库初始化
-- 运行方式：docker compose up -d postgres 后自动执行

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- 部门/小组表
CREATE TABLE IF NOT EXISTS departments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(128) UNIQUE NOT NULL,
    description VARCHAR(256) DEFAULT '',
    leader_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 用户表
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(64) UNIQUE NOT NULL,
    email VARCHAR(128) UNIQUE NOT NULL,
    hashed_password VARCHAR(256) NOT NULL,
    role VARCHAR(32) NOT NULL DEFAULT 'general'
        CHECK (role IN ('admin', 'dept_manager', 'project_manager', 'general')),
    department VARCHAR(128) DEFAULT '',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 文件/文件夹表
CREATE TABLE IF NOT EXISTS files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(512) NOT NULL,
    is_folder BOOLEAN DEFAULT FALSE,
    parent_id UUID REFERENCES files(id) ON DELETE CASCADE,
    mime_type VARCHAR(128) DEFAULT '',
    size_bytes BIGINT DEFAULT 0,
    storage_path VARCHAR(1024) DEFAULT '',
    uploaded_by UUID REFERENCES users(id),
    project_id VARCHAR(64) DEFAULT '',
    confidentiality_level INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_files_parent ON files(parent_id);
CREATE INDEX IF NOT EXISTS idx_files_uploaded ON files(uploaded_by);

-- 权限表（ACL）
CREATE TABLE IF NOT EXISTS permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type VARCHAR(32) NOT NULL DEFAULT 'file'
        CHECK (resource_type IN ('file', 'folder', 'project')),
    resource_id UUID NOT NULL,
    grantee_type VARCHAR(32) NOT NULL
        CHECK (grantee_type IN ('user', 'role', 'department', 'project')),
    grantee_value VARCHAR(128) NOT NULL,
    action VARCHAR(32) NOT NULL
        CHECK (action IN ('preview', 'download', 'edit', 'admin')),
    granted_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(resource_type, resource_id, grantee_type, grantee_value, action)
);
CREATE INDEX IF NOT EXISTS idx_perm_resource ON permissions(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_perm_grantee ON permissions(grantee_type, grantee_value);

-- 审计日志表
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID,
    username VARCHAR(128) DEFAULT 'anonymous',
    action VARCHAR(64) NOT NULL,
    resource_type VARCHAR(64) DEFAULT '',
    resource_id UUID,
    resource_name VARCHAR(512) DEFAULT '',
    result VARCHAR(32) DEFAULT 'success',
    detail TEXT DEFAULT '',
    ip_address VARCHAR(45),
    user_agent TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(username);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_time ON audit_logs(created_at DESC);

-- 文案模板表
CREATE TABLE IF NOT EXISTS copy_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(128) NOT NULL,
    platform_type VARCHAR(32) DEFAULT 'wechat',
    template_content TEXT NOT NULL,
    system_prompt TEXT DEFAULT '',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 文案生成历史表
CREATE TABLE IF NOT EXISTS copy_histories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    platform_type VARCHAR(32) DEFAULT 'wechat',
    topic VARCHAR(256) DEFAULT '',
    core_info TEXT DEFAULT '',
    target_audience VARCHAR(256) DEFAULT '',
    tone VARCHAR(64) DEFAULT '',
    purpose VARCHAR(64) DEFAULT '',
    content TEXT DEFAULT '',
    model VARCHAR(64) DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_copy_hist_user ON copy_histories(user_id);

-- 默认管理员
INSERT INTO users (username, email, hashed_password, role, department)
VALUES ('admin', 'admin@company.local',
        '$2b$12$w6d2ExDXt/iQdgheFBphyu7VZbzL398c3D9l.GPVeAN6OCYHRbzEi',
        'admin', '技术部')
ON CONFLICT (username) DO NOTHING;
-- 密码: admin123
