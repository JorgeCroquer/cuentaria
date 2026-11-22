import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/visibility_providers.dart';

/// Replaces the numeric run of a preformatted amount with `••••`, keeping
/// everything else (currency symbol, sign, suffix) in place — e.g.
/// `'-\$1,234.56'` becomes `'-\$••••'` and `'1,234.56 USD'` becomes
/// `'•••• USD'`.
String maskAmount(String formatted) =>
    formatted.replaceAll(RegExp(r'[0-9][0-9.,]*'), '••••');

/// The single place that consults [balancesHiddenProvider] (#333) to decide
/// whether a preformatted amount renders plain or masked via [maskAmount].
/// [HeroAmount] and [SignedAmountText] render their figure through this so
/// every money figure in the app obeys the same global eye toggle.
class AmountText extends ConsumerWidget {
  const AmountText(this.amount, {super.key, this.style, this.amountKey});

  final String amount;
  final TextStyle? style;
  final Key? amountKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(balancesHiddenProvider);
    return Text(
      hidden ? maskAmount(amount) : amount,
      key: amountKey,
      style: style,
    );
  }
}
