import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

const gemmaTermsAsset = 'licenses/gemma/terms.txt';
const gemmaPolicyAsset = 'licenses/gemma/prohibited_use_policy.txt';

/// The restriction Gemma Terms 3.1 asks to be an enforceable provision of the terms that govern use.
const gemmaUseRestriction =
    'You must not use a Gemma model in Berea for any use listed in the Gemma Prohibited Use Policy, '
    'which is part of these terms, or in breach of a law that applies to you.';

/// What Berea promises and asks of anyone who uses it.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of use')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const _Heading('Berea'),
              const Text(
                'Berea is free software under the MIT licence. Its answers come from a language '
                'model running on your device and can be wrong, so check them against the verses '
                'they cite.',
              ),
              const _Heading('Gemma models'),
              const Text(
                'Gemma 3 1B is a Google Gemma model. When you download or use it in Berea, it is '
                'provided under and subject to the Gemma Terms of Use found at '
                'ai.google.dev/gemma/terms, and you agree to those terms.',
              ),
              const SizedBox(height: 8),
              const Text(gemmaUseRestriction),
              const SizedBox(height: 8),
              const Text(
                'Gemma 4 and any other model in Berea come under their own licences, listed '
                'under Licences and sources.',
              ),
              const SizedBox(height: 16),
              _TextTile('Gemma Terms of Use', gemmaTermsAsset),
              _TextTile('Gemma Prohibited Use Policy', gemmaPolicyAsset),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _TextTile extends StatelessWidget {
  final String title;
  final String asset;
  const _TextTile(this.title, this.asset);

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _TextFileScreen(title, asset)),
    ),
  );
}

/// A bundled text file, as published, so the full terms are always readable offline.
class _TextFileScreen extends StatelessWidget {
  final String title;
  final String asset;
  const _TextFileScreen(this.title, this.asset);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(asset),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: contentMaxWidth),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(snap.data!),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Asks for agreement before a model that carries a notice is downloaded; true when [model]
/// needs none or the user has already agreed to this version of the terms.
Future<bool> confirmModelTerms(BuildContext context, AppState state, EdgeModel model) async {
  if (model.notice == null || state.termsAccepted) return true;
  final agreed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Gemma terms'),
      content: SingleChildScrollView(child: Text('${model.notice}.\n\n$gemmaUseRestriction')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            dialog,
          ).push(MaterialPageRoute<void>(builder: (_) => const TermsScreen())),
          child: const Text('Read the terms'),
        ),
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Agree and download'),
        ),
      ],
    ),
  );
  if (agreed != true) return false;
  await state.acceptTerms();
  return true;
}
