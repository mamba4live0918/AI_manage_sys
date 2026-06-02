import 'package:flutter/material.dart';
import '../models/finance_models.dart';
import '../services/api_client.dart';

/// A tree-selector widget that displays budgets in hierarchy:
///   总预算 → 季度 → 部门
/// Returns the selected budget_id via [onChanged].
class BudgetTreeSelector extends StatefulWidget {
  final String? initialBudgetId;
  final ValueChanged<String?> onChanged;
  final String? label;
  final bool showClearButton;

  const BudgetTreeSelector({
    super.key,
    this.initialBudgetId,
    required this.onChanged,
    this.label,
    this.showClearButton = true,
  });

  @override
  State<BudgetTreeSelector> createState() => _BudgetTreeSelectorState();
}

class _BudgetTreeSelectorState extends State<BudgetTreeSelector> {
  final ApiClient _api = ApiClient();
  List<BudgetData> _budgets = [];
  bool _loading = true;
  String? _selectedId;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialBudgetId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/finance/budgets');
      final raw = List<Map<String, dynamic>>.from(resp.data['items']);
      setState(() {
        _budgets = raw.map((j) => BudgetData.fromJson(j)).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<BudgetData> _roots() => _budgets.where((b) => b.parentId == null).toList();
  List<BudgetData> _children(String pid) => _budgets.where((b) => b.parentId == pid).toList();

  void _onTap(BudgetData? budget) {
    if (budget == null) {
      setState(() => _selectedId = null);
      widget.onChanged(null);
      return;
    }
    if (_selectedId == budget.id) {
      setState(() {
        if (_expanded.contains(budget.id)) {
          _expanded.remove(budget.id);
        } else {
          _expanded.add(budget.id);
        }
      });
      return;
    }
    setState(() {
      _selectedId = budget.id;
      _expanded.add(budget.id);
    });
    widget.onChanged(_selectedId);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final selectedBg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.08);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (widget.label != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(widget.label!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ),
      if (_loading)
        const SizedBox(height: 40, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
      else
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.showClearButton)
                _node(null, '不关联预算', 0, selectedBg, isDark, isDeselect: true),
              for (final root in _roots()) ...[
                _node(root, root.name, 0, selectedBg, isDark),
                if (_expanded.contains(root.id))
                  for (final child in _children(root.id)) ...[
                    _node(child, child.name, 1, selectedBg, isDark),
                    if (_expanded.contains(child.id))
                      for (final gc in _children(child.id))
                        _node(gc, gc.name, 2, selectedBg, isDark),
                  ],
              ],
            ]),
          ),
        ),
    ]);
  }

  Widget _node(BudgetData? budget, String label, int depth, Color selectedBg, bool isDark, {bool isDeselect = false}) {
    final isSelected = isDeselect ? _selectedId == null : budget != null && _selectedId == budget.id;
    final hasChildren = budget != null && _budgets.any((b) => b.parentId == budget.id);

    return InkWell(
      onTap: () {
        if (isDeselect) {
          _onTap(null);
        } else {
          _onTap(budget);
        }
      },
      child: Container(
        padding: EdgeInsets.only(left: 8.0 + depth * 20.0, right: 8, top: 8, bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          if (budget != null && hasChildren)
            Icon(
              _expanded.contains(budget.id) ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
              size: 16, color: isDark ? Colors.white54 : Colors.black45,
            )
          else
            const SizedBox(width: 16),
          const SizedBox(width: 4),
          if (isSelected)
            Icon(Icons.check_circle, size: 16, color: Theme.of(context).colorScheme.primary)
          else
            Icon(Icons.radio_button_unchecked, size: 16, color: isDark ? Colors.white38 : Colors.black26),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (budget != null)
            Text(
              budget.quarter != null ? '${budget.year} Q${budget.quarter}' : '${budget.year}年',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
            ),
        ]),
      ),
    );
  }
}
