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

-- ── Phase 4: PM ──

CREATE TABLE IF NOT EXISTS pm_projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(256) NOT NULL,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    stage VARCHAR(64) DEFAULT 'initiation',
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    budget FLOAT DEFAULT 0.0,
    description TEXT DEFAULT '',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pm_project_dept ON pm_projects(department_id);

CREATE TABLE IF NOT EXISTS visit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES pm_projects(id) ON DELETE CASCADE NOT NULL,
    content TEXT DEFAULT '',
    location VARCHAR(256) DEFAULT '',
    visited_at TIMESTAMPTZ DEFAULT now(),
    recorded_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_visit_log_project ON visit_logs(project_id);

CREATE TABLE IF NOT EXISTS coursewares (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES pm_projects(id) ON DELETE SET NULL,
    title VARCHAR(256) NOT NULL,
    type VARCHAR(64) DEFAULT 'document',
    content TEXT DEFAULT '',
    file_id UUID REFERENCES files(id) ON DELETE SET NULL,
    version INTEGER DEFAULT 1,
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_courseware_project ON coursewares(project_id);

CREATE TABLE IF NOT EXISTS project_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES pm_projects(id) ON DELETE CASCADE NOT NULL,
    report_type VARCHAR(64) DEFAULT 'progress',
    content TEXT DEFAULT '',
    content_html TEXT DEFAULT '',
    model VARCHAR(64) DEFAULT '',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_report_project ON project_reports(project_id);

-- ── Phase 4: HR ──

CREATE TABLE IF NOT EXISTS employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(128) NOT NULL,
    position VARCHAR(128) DEFAULT '',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    hire_date TIMESTAMPTZ,
    status VARCHAR(32) DEFAULT 'active',
    phone VARCHAR(64) DEFAULT '',
    email VARCHAR(256) DEFAULT '',
    salary INTEGER DEFAULT 0,
    contract_start TIMESTAMPTZ,
    contract_end TIMESTAMPTZ,
    file_id UUID REFERENCES files(id) ON DELETE SET NULL,
    notes TEXT DEFAULT '',
    user_id UUID REFERENCES users(id) ON DELETE SET NULL UNIQUE,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_employee_dept ON employees(department_id);

CREATE TABLE IF NOT EXISTS resumes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(128) NOT NULL,
    content TEXT DEFAULT '',
    file_id UUID REFERENCES files(id) ON DELETE SET NULL,
    match_score FLOAT DEFAULT 0.0,
    match_result TEXT DEFAULT '',
    status VARCHAR(32) DEFAULT 'new',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS approvals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    approval_type VARCHAR(32) DEFAULT 'leave',
    applicant_id UUID REFERENCES users(id) NOT NULL,
    status VARCHAR(32) DEFAULT 'pending',
    content TEXT DEFAULT '',
    approver_id UUID REFERENCES users(id),
    comment TEXT DEFAULT '',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_approval_applicant ON approvals(applicant_id);

CREATE TABLE IF NOT EXISTS approval_steps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    approval_id UUID REFERENCES approvals(id) ON DELETE CASCADE NOT NULL,
    level INTEGER DEFAULT 1,
    approver_id UUID REFERENCES users(id),
    status VARCHAR(32) DEFAULT 'pending',
    comment TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_approval_steps_approval ON approval_steps(approval_id);

-- ── Phase 4: Interview Scheduling ──

CREATE TABLE IF NOT EXISTS interviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    candidate_name VARCHAR(128) NOT NULL,
    position VARCHAR(128) DEFAULT '',
    scheduled_at TIMESTAMPTZ,
    duration_minutes INTEGER DEFAULT 30,
    status VARCHAR(32) DEFAULT 'scheduled',
    interviewer_id UUID REFERENCES users(id),
    notes TEXT DEFAULT '',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_interview_dept ON interviews(department_id);
CREATE INDEX IF NOT EXISTS idx_interview_scheduled ON interviews(scheduled_at);

-- ── Phase 4: Finance ──

CREATE TABLE IF NOT EXISTS settlements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES pm_projects(id) ON DELETE SET NULL,
    amount FLOAT DEFAULT 0.0,
    status VARCHAR(32) DEFAULT 'pending',
    settlement_date TIMESTAMPTZ,
    invoice_no VARCHAR(128) DEFAULT '',
    notes TEXT DEFAULT '',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_settlement_dept ON settlements(department_id);

CREATE TABLE IF NOT EXISTS expenses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES pm_projects(id) ON DELETE SET NULL,
    amount FLOAT DEFAULT 0.0,
    category VARCHAR(64) DEFAULT 'other',
    description TEXT DEFAULT '',
    status VARCHAR(32) DEFAULT 'pending',
    submitted_by UUID REFERENCES users(id),
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_expense_dept ON expenses(department_id);

CREATE TABLE IF NOT EXISTS vouchers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    settlement_id UUID REFERENCES settlements(id) ON DELETE SET NULL,
    expense_id UUID REFERENCES expenses(id) ON DELETE SET NULL,
    file_id UUID REFERENCES files(id) ON DELETE SET NULL,
    type VARCHAR(64) DEFAULT 'invoice',
    description TEXT DEFAULT '',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_voucher_settlement ON vouchers(settlement_id);
CREATE INDEX IF NOT EXISTS idx_voucher_expense ON vouchers(expense_id);

-- 默认管理员
INSERT INTO users (username, email, hashed_password, role, department)
VALUES ('admin', 'admin@company.local',
        '$2b$12$w6d2ExDXt/iQdgheFBphyu7VZbzL398c3D9l.GPVeAN6OCYHRbzEi',
        'admin', '技术部')
ON CONFLICT (username) DO NOTHING;
-- 密码: admin123

-- Phase 4 migration: add expense_id to vouchers
ALTER TABLE vouchers ADD COLUMN IF NOT EXISTS expense_id UUID REFERENCES expenses(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_voucher_expense ON vouchers(expense_id);

-- Phase 4 migration: add employee salary/contract/file fields
ALTER TABLE employees ADD COLUMN IF NOT EXISTS salary INTEGER DEFAULT 0;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS contract_start TIMESTAMPTZ;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS contract_end TIMESTAMPTZ;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS file_id UUID REFERENCES files(id) ON DELETE SET NULL;

-- Phase 4.5 migration: link employee to system user
ALTER TABLE employees ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE SET NULL UNIQUE;

-- 2026-05-29: finance module upgrade
CREATE TABLE IF NOT EXISTS invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES pm_projects(id) ON DELETE SET NULL,
    invoice_no VARCHAR(128) DEFAULT '',
    amount FLOAT DEFAULT 0.0,
    tax_amount FLOAT DEFAULT 0.0,
    tax_rate FLOAT DEFAULT 0.13,
    status VARCHAR(32) DEFAULT 'draft',
    issue_date TIMESTAMPTZ,
    due_date TIMESTAMPTZ,
    notes TEXT DEFAULT '',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    invoice_id UUID REFERENCES invoices(id) ON DELETE SET NULL,
    amount FLOAT DEFAULT 0.0,
    payment_date TIMESTAMPTZ,
    payment_method VARCHAR(32) DEFAULT 'bank_transfer',
    ref_no VARCHAR(128) DEFAULT '',
    notes TEXT DEFAULT '',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS budgets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    project_id UUID REFERENCES pm_projects(id) ON DELETE SET NULL,
    name VARCHAR(128) DEFAULT '',
    year INTEGER DEFAULT 2026,
    quarter INTEGER,
    total_amount FLOAT DEFAULT 0.0,
    used_amount FLOAT DEFAULT 0.0,
    status VARCHAR(32) DEFAULT 'active',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Migration: add invoice_id to settlements
ALTER TABLE settlements ADD COLUMN IF NOT EXISTS invoice_id UUID REFERENCES invoices(id) ON DELETE SET NULL;

-- Migration: add invoice_id to vouchers
ALTER TABLE vouchers ADD COLUMN IF NOT EXISTS invoice_id UUID REFERENCES invoices(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_voucher_invoice ON vouchers(invoice_id);

-- 2026-05-29: add seller/buyer info to invoices
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS seller_name VARCHAR(128) DEFAULT '';
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS seller_tax_id VARCHAR(64) DEFAULT '';
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS buyer_name VARCHAR(128) DEFAULT '';
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS buyer_tax_id VARCHAR(64) DEFAULT '';
