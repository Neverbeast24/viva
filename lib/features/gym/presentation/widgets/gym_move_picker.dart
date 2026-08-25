import 'package:flutter/material.dart';

import '../../../../shared/models/gym_exercise.dart';
import '../../data/gym_labels.dart';

class GymMovePickerField extends StatefulWidget {
  const GymMovePickerField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.catalog,
    this.label = 'Move name',
  });

  final String value;
  final ValueChanged<String> onChanged;
  final List<GymExercise> catalog;
  final String label;

  @override
  State<GymMovePickerField> createState() => _GymMovePickerFieldState();
}

class _GymMovePickerFieldState extends State<GymMovePickerField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant GymMovePickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<String> _optionsFor(String raw) {
    final matches = filterGymMoveCatalog(raw, widget.catalog);
    final names = [for (final item in matches) item.name];
    final query = raw.trim();
    final exact = names.any((name) => name.toLowerCase() == query.toLowerCase());
    if (query.length >= 2 && !exact) names.add(query);
    return names;
  }

  GymExercise? _match(String name) {
    final needle = name.toLowerCase();
    for (final item in widget.catalog) {
      if (item.name.toLowerCase() == needle) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focus,
      displayStringForOption: (option) => option,
      optionsBuilder: (value) => _optionsFor(value.text),
      onSelected: widget.onChanged,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            suffixIcon: const Icon(Icons.search_rounded),
          ),
          onChanged: widget.onChanged,
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: options.isEmpty
                  ? const ListTile(
                      dense: true,
                      title: Text('Type a move name.'),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final name = options.elementAt(index);
                        final item = _match(name);
                        return ListTile(
                          dense: true,
                          title: Text(name),
                          subtitle: Text(
                            item == null
                                ? 'Use this name'
                                : [
                                    if (item.muscleGroup.isNotEmpty) humanizeLabel(item.muscleGroup),
                                    if (item.equipment.isNotEmpty) humanizeLabel(item.equipment),
                                  ].join(' · '),
                          ),
                          onTap: () => onSelected(name),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}
