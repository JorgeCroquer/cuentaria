import 'package:flutter/material.dart';

/// Literal transparency text (issue #223, ADR-0023 §7) — the same text also
/// lives verbatim in the repo root's `PRIVACY.md`, which Google requires to
/// approve the app.
const cloudCopyTransparencyText =
    'Cuentaria guarda una copia de tus datos en TU Google Drive, en '
    'una carpeta que solo esta app ve. No tenemos servidor: no vemos, '
    'no guardamos y no podemos recuperar tus datos.';

/// Transparency text shown at the top of the Cloud Copy screen, with a link
/// to the privacy policy (`PRIVACY.md`) carrying the same text.
class TransparencySection extends StatelessWidget {
  const TransparencySection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(cloudCopyTransparencyText),
        TextButton(
          key: const Key('privacyPolicyLink'),
          onPressed:
              () => showDialog<void>(
                context: context,
                builder:
                    (context) => const AlertDialog(
                      content: Text(cloudCopyTransparencyText),
                    ),
              ),
          child: const Text('Política de privacidad'),
        ),
      ],
    );
  }
}
