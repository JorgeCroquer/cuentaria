/// Typed, optional funding target for a user Envelope.
///
/// Serialized as a JSON object inside the `meta` column under the key
/// `"target"`.  System envelopes (`role != none`) must never carry a target.
///
/// Amounts are in **USD cents (int)** — never double.
sealed class EnvelopeTarget {
  const EnvelopeTarget();

  /// Deserializes from the `"target"` sub-object stored in `meta`.
  factory EnvelopeTarget.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'none' => const NoTarget(),
      'cap' => Cap(amountUsd: json['amount_usd'] as int),
      'goal_line' => GoalLine(
          amountUsd: json['amount_usd'] as int,
          dueDate: json['due_date'] == null
              ? null
              : DateTime.parse(json['due_date'] as String),
        ),
      _ => throw FormatException('Unknown EnvelopeTarget type: $type'),
    };
  }

  Map<String, dynamic> toJson();
}

/// No funding target — the default for every new user Envelope.
final class NoTarget extends EnvelopeTarget {
  const NoTarget();

  @override
  Map<String, dynamic> toJson() => {'type': 'none'};

  @override
  bool operator ==(Object other) => other is NoTarget;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A spending cap: the Envelope balance must not exceed [amountUsd] cents.
/// Used by the cascade engine's `fill-to-cap` step.
final class Cap extends EnvelopeTarget {
  final int amountUsd;

  const Cap({required this.amountUsd});

  @override
  Map<String, dynamic> toJson() => {'type': 'cap', 'amount_usd': amountUsd};

  @override
  bool operator ==(Object other) =>
      other is Cap && other.amountUsd == amountUsd;

  @override
  int get hashCode => Object.hash('cap', amountUsd);
}

/// A savings goal: track progress towards [amountUsd] cents by optional
/// [dueDate].  Read by Patrimony (S2); never enforced by the cascade engine.
final class GoalLine extends EnvelopeTarget {
  final int amountUsd;
  final DateTime? dueDate;

  const GoalLine({required this.amountUsd, this.dueDate});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'goal_line',
        'amount_usd': amountUsd,
        if (dueDate != null) 'due_date': dueDate!.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is GoalLine &&
      other.amountUsd == amountUsd &&
      other.dueDate == dueDate;

  @override
  int get hashCode => Object.hash('goal_line', amountUsd, dueDate);
}
