import 'package:flutter/material.dart';

/// An outlined chip disclosing a rate's [name] and its preformatted [value]
/// (which carries the value and its age/staleness in one string).
class RateChip extends StatelessWidget {
  const RateChip({
    super.key,
    required this.name,
    required this.value,
    this.valueKey,
    this.isPrimary = false,
  });

  final String name;
  final String value;
  final Key? valueKey;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Chip(
      shape: StadiumBorder(side: BorderSide(color: colorScheme.outlineVariant)),
      backgroundColor: Colors.transparent,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$name ',
            style: isPrimary ? TextStyle(color: colorScheme.primary) : null,
          ),
          Flexible(
            child: Text(value, key: valueKey, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
