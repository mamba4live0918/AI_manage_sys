import 'package:flutter/material.dart';

/// Searchable department autocomplete for finance edit dialog.
class DeptAutocomplete extends StatelessWidget {
  final Map<String, String> deptNames; // id → name
  final String? initialId;
  final ValueChanged<String?> onChanged;

  const DeptAutocomplete({
    super.key,
    required this.deptNames,
    this.initialId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = deptNames.entries.map((e) => _DeptOption(e.key, e.value)).toList();
    final initialValue = initialId != null ? options.where((o) => o.id == initialId).firstOrNull : null;

    return Autocomplete<_DeptOption>(
      initialValue: initialValue != null ? TextEditingValue(text: initialValue.name) : null,
      displayStringForOption: (o) => o.name,
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return options;
        final q = textEditingValue.text.toLowerCase();
        return options.where((o) => o.name.toLowerCase().contains(q));
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        if (initialValue != null && controller.text.isEmpty) {
          controller.text = initialValue.name;
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(labelText: '部门', isDense: true),
          onSubmitted: (_) => onSubmit(),
        );
      },
      onSelected: (o) => onChanged(o.id),
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: options.map((o) => ListTile(
                  dense: true,
                  title: Text(o.name, style: const TextStyle(fontSize: 13)),
                  onTap: () => onSelected(o),
                )).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeptOption {
  final String id;
  final String name;
  const _DeptOption(this.id, this.name);
}
