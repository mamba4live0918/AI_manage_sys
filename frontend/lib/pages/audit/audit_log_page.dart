import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/watermark.dart';
import '../../widgets/shimmer.dart';

class AuditLogPage extends ConsumerStatefulWidget {
  const AuditLogPage({super.key});

  @override
  ConsumerState<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends ConsumerState<AuditLogPage> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _logs = [];
  int _total = 0;
  int _page = 1;
  bool _loading = false;
  String? _filterAction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/audit/logs', queryParameters: {
        'page': _page,
        'page_size': 50,
        if (_filterAction != null) 'action': _filterAction,
      });
      setState(() {
        _logs = List<Map<String, dynamic>>.from(resp.data['items']);
        _total = resp.data['total'] ?? 0;
      });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Color _actionColor(String action) {
    if (action.contains('delete') || action.contains('rejected')) return AppTheme.red;
    if (action.contains('create') || action.contains('upload') || action.contains('generate') || action.contains('approved')) return AppTheme.green;
    if (action.contains('update')) return AppTheme.blue;
    if (action.contains('preview') || action.contains('download')) return AppTheme.blue;
    return Colors.grey;
  }

  String _actionLabel(String action) {
    if (action == 'preview') return '预览';
    if (action == 'preview_close') return '关闭预览';
    if (action == 'download') return '下载';
    if (action == 'upload') return '上传';
    if (action == 'delete') return '删除';
    if (action == 'create_folder') return '新建文件夹';
    if (action == 'set_level') return '设置级别';
    if (action == 'permission_change') return '权限变更';
    if (action == 'dept_create') return '创建部门';
    if (action == 'dept_update') return '修改部门';
    if (action == 'dept_delete') return '删除部门';
    if (action == 'dept_set_leader') return '设置部门长';
    if (action == 'dept_add_member') return '添加成员';
    if (action == 'dept_remove_member') return '移除成员';
    if (action.contains('denied')) return '无权限';
    // Bidding
    if (action == 'template_create') return '创建合同模板';
    if (action == 'template_update') return '更新合同模板';
    if (action == 'template_delete') return '删除合同模板';
    if (action == 'contract_generate') return '生成合同';
    if (action == 'contract_update') return '更新合同';
    if (action == 'contract_delete') return '删除合同';
    if (action == 'knowledge_doc_create') return '创建投标知识';
    if (action == 'knowledge_doc_upload') return '上传投标知识';
    if (action == 'knowledge_doc_file_delete') return '删除投标知识文件';
    if (action == 'knowledge_doc_update') return '更新投标知识';
    if (action == 'knowledge_doc_delete') return '删除投标知识';
    if (action == 'process_create') return '创建投标流程';
    if (action == 'process_update') return '更新投标流程';
    if (action == 'process_delete') return '删除投标流程';
    if (action == 'supplier_create') return '添加供应商';
    if (action == 'supplier_update') return '更新供应商';
    if (action == 'supplier_delete') return '删除供应商';
    if (action == 'instructor_create') return '添加讲师';
    if (action == 'instructor_update') return '更新讲师';
    if (action == 'instructor_delete') return '删除讲师';
    if (action == 'course_match') return '课程匹配';
    // HR
    if (action == 'employee_update') return '更新员工信息';
    if (action == 'resume_create') return '创建简历';
    if (action == 'resume_upload') return '上传简历';
    if (action == 'resume_update') return '更新简历';
    if (action == 'resume_delete') return '删除简历';
    if (action == 'resume_match') return '简历评估';
    if (action == 'approval_create') return '提交审批';
    if (action == 'approval_approved') return '审批通过';
    if (action == 'approval_rejected') return '审批驳回';
    if (action == 'approval_delete') return '删除审批';
    if (action == 'approval_step_approved') return '审批步骤通过';
    if (action == 'approval_step_rejected') return '审批步骤驳回';
    if (action == 'interview_create') return '安排面试';
    if (action == 'interview_update') return '更新面试';
    if (action == 'interview_delete') return '删除面试';
    // Finance
    if (action == 'settlement_create') return '创建结算';
    if (action == 'settlement_update') return '更新结算';
    if (action == 'settlement_delete') return '删除结算';
    if (action == 'expense_create') return '创建支出';
    if (action == 'expense_approved') return '支出已通过';
    if (action == 'expense_rejected') return '支出已驳回';
    if (action == 'expense_delete') return '删除支出';
    if (action == 'expense_paid') return '支出已支付';
    if (action == 'voucher_create') return '上传凭证';
    if (action == 'voucher_upload') return '上传凭证文件';
    if (action == 'voucher_delete') return '删除凭证';
    if (action == 'invoice_create') return '创建发票';
    if (action == 'invoice_update') return '更新发票';
    if (action == 'invoice_delete') return '删除发票';
    if (action == 'payment_create') return '添加收款';
    if (action == 'payment_delete') return '删除收款';
    if (action == 'budget_create') return '创建预算';
    if (action == 'budget_update') return '更新预算';
    if (action == 'budget_delete') return '删除预算';
    // Marketing
    if (action == 'customer_create') return '创建客户';
    if (action == 'customer_update') return '更新客户';
    if (action == 'customer_delete') return '删除客户';
    if (action == 'behavior_record') return '行为记录';
    if (action == 'satisfaction_record') return '满意度记录';
    if (action == 'churn_warning_create') return '流失预警';
    if (action == 'demand_prediction') return '需求预测';
    if (action == 'proposal_generate') return '生成方案';
    if (action == 'proposal_update') return '更新方案';
    if (action == 'proposal_delete') return '删除方案';
    if (action == 'project_create') return '创建项目';
    if (action == 'project_update') return '更新项目';
    if (action == 'project_delete') return '删除项目';
    if (action == 'brief_generate') return '生成简报';
    if (action == 'interaction_record') return '互动记录';
    if (action == 'knowledge_create') return '创建知识';
    if (action == 'knowledge_upload') return '上传知识';
    if (action == 'knowledge_file_delete') return '删除知识文件';
    if (action == 'knowledge_update') return '更新知识';
    if (action == 'knowledge_delete') return '删除知识';
    if (action == 'knowledge_qa') return '知识问答';
    // PM
    if (action == 'visit_log_create') return '创建拜访记录';
    if (action == 'courseware_create') return '创建课件';
    if (action == 'courseware_upload') return '上传课件';
    if (action == 'courseware_update') return '更新课件';
    if (action == 'courseware_delete') return '删除课件';
    if (action == 'report_generate') return '生成报告';
    if (action == 'copy_generate') return 'AI文案生成';
    return action;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildHeader(theme, isDark),
            const SizedBox(height: 8),
            _buildFilterChips(theme, isDark),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '$_total 条记录',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                  const Spacer(),
                  _PageDots(
                    page: _page,
                    total: (_total / 50).ceil(),
                    onPrev: _page > 1 ? () { _page--; _load(); } : null,
                    onNext: _page * 50 < _total ? () { _page++; _load(); } : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const ShimmerList()
                  : _logs.isEmpty
                      ? Center(
                          child: Text('暂无记录',
                              style: TextStyle(
                                  color: theme.colorScheme.onSurface.withAlpha(100), fontSize: 17)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _logs.length,
                          itemBuilder: (_, i) => _buildLogItem(_logs[i], isDark),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 4),
      child: Row(
        children: [
          Text('操作审计', style: theme.textTheme.headlineLarge),
        ],
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme, bool isDark) {
    final actions = [
      null,
      'upload',
      'download',
      'preview',
      'delete',
      'create_folder',
      'set_level',
      'copy_generate',
      'permission_change',
      'dept_create',
      'dept_set_leader',
      'dept_add_member',
      'dept_remove_member',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: actions.map((a) {
          final selected = _filterAction == a;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                _filterAction = a;
                _page = 1;
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.blue
                      : (isDark ? AppTheme.darkElevated : const Color(0xFFE8E8ED)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  a == null ? '全部' : _actionLabel(a),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: selected ? Colors.white : (isDark ? Colors.white.withAlpha(180) : Colors.black.withAlpha(160)),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log, bool isDark) {
    final action = log['action'] ?? '';
    final color = _actionColor(action);
    final success = log['result'] == 'success';

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: color.withAlpha(isDark ? 25 : 18),
                ),
                child: Icon(
                  success ? Icons.check_circle_rounded : Icons.close_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${log['username'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _actionLabel(action),
                            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      log['resource_name'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: (isDark ? Colors.white : Colors.black).withAlpha(120),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(log['created_at'] ?? ''),
                style: TextStyle(
                  fontSize: 13,
                  color: (isDark ? Colors.white : Colors.black).withAlpha(100),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

class _PageDots extends StatelessWidget {
  final int page;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _PageDots({
    required this.page,
    required this.total,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DotButton(icon: Icons.chevron_left_rounded, enabled: onPrev != null, onTap: onPrev),
        const SizedBox(width: 2),
        for (int i = 0; i < total && i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(
            width: i == page - 1 ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: i == page - 1 ? AppTheme.blue : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withAlpha(30)
                  : Colors.black.withAlpha(15)),
            ),
          ),
        ],
        const SizedBox(width: 2),
        _DotButton(icon: Icons.chevron_right_rounded, enabled: onNext != null, onTap: onNext),
      ],
    );
  }
}

class _DotButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _DotButton({required this.icon, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          color: enabled
              ? AppTheme.blue.withAlpha(15)
              : Colors.transparent,
        ),
        child: Icon(icon, size: 18,
            color: enabled ? AppTheme.blue : Colors.grey.withAlpha(100)),
      ),
    );
  }
}
