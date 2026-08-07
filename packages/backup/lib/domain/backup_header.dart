/// Per-kind line counts declared in the [BackupHeader], checked against the
/// lines actually written so a truncated file is caught by the count instead
/// of by a human noticing missing rows.
class BackupCounts {
  final int event;
  final int account;
  final int envelope;
  final int cascade;
  final int rate;

  const BackupCounts({
    required this.event,
    required this.account,
    required this.envelope,
    required this.cascade,
    required this.rate,
  });

  factory BackupCounts.fromJson(Map<String, dynamic> json) {
    return BackupCounts(
      event: json['event'] as int,
      account: json['account'] as int,
      envelope: json['envelope'] as int,
      cascade: json['cascade'] as int,
      rate: json['rate'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'event': event,
    'account': account,
    'envelope': envelope,
    'cascade': cascade,
    'rate': rate,
  };

  @override
  bool operator ==(Object other) =>
      other is BackupCounts &&
      other.event == event &&
      other.account == account &&
      other.envelope == envelope &&
      other.cascade == cascade &&
      other.rate == rate;

  @override
  int get hashCode => Object.hash(event, account, envelope, cascade, rate);

  @override
  String toString() =>
      'BackupCounts(event: $event, account: $account, envelope: $envelope, '
      'cascade: $cascade, rate: $rate)';
}

/// The first line of every Backup File (ADR-0021 §1-2).
class BackupHeader {
  final int format;
  final String app;
  final DateTime exportedAt;
  final BackupCounts counts;

  const BackupHeader({
    required this.format,
    required this.app,
    required this.exportedAt,
    required this.counts,
  });

  factory BackupHeader.fromJson(Map<String, dynamic> json) {
    return BackupHeader(
      format: json['format'] as int,
      app: json['app'] as String,
      exportedAt: DateTime.parse(json['exportedAt'] as String),
      counts: BackupCounts.fromJson(json['counts'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': 'header',
    'format': format,
    'app': app,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'counts': counts.toJson(),
  };
}
