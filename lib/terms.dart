import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

const gemmaTermsAsset = 'licenses/gemma/terms.txt';
const gemmaPolicyAsset = 'licenses/gemma/prohibited_use_policy.txt';
const supertonicLicenceAsset = 'licenses/supertonic/LICENSE.txt';

/// OpenRAIL-M paragraph 5 asks that every user of the voice is bound by Attachment A; this is
/// that list, in plain words, and the licence text is a tap away.
const supertonicUseRestriction =
    'You must not use the Supertonic voice, or anything made with it, to break the law; to harm '
    'or exploit minors; to spread false information meant to harm others; to spread personal '
    'information that can harm someone; to publish what it says without saying clearly that it '
    'is machine generated; to defame, disparage or harass anyone; to impersonate anyone without '
    'their consent; for fully automated decisions that harm a person\'s legal rights; to '
    'discriminate, or to exploit the weaknesses of a group of people; to give medical advice; or '
    'for law enforcement, justice, immigration or asylum decisions. These are the use '
    'restrictions in Attachment A of its licence, and they are part of these terms.';

/// The restriction Gemma Terms 3.1 asks to be an enforceable provision of the terms that govern
/// use, worded as 3.2 words it.
const gemmaUseRestriction =
    'You must not use any Gemma model, in Berea or anywhere else, for a use listed in the Gemma '
    'Prohibited Use Policy, which is part of these terms, or in breach of applicable laws and '
    'regulations.';

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
              const _Heading('Supertonic voice'),
              const Text(
                'Listen reads deep dives aloud with Supertonic 3 by Supertone, under the '
                'BigScience Open RAIL-M License. When you download or use it in Berea, you agree '
                'to that licence.',
              ),
              const SizedBox(height: 8),
              const Text(supertonicUseRestriction),
              const SizedBox(height: 16),
              const _TextTile('Open RAIL-M License', supertonicLicenceAsset),
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
    subtitle: const Text('Readable offline'),
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
  final agreed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ModelTermsScreen(model: model, wifiOnly: state.wifiOnly),
    ),
  );
  if (agreed != true) return false;
  await state.acceptTerms();
  return true;
}

const _stepSize = 28.0;

/// Before you download: the three things to know about a model that carries a notice. Pops true
/// when the reader agrees.
class ModelTermsScreen extends StatelessWidget {
  final EdgeModel model;
  final bool wifiOnly;
  const ModelTermsScreen({super.key, required this.model, required this.wifiOnly});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Before you download')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: [
                    Text('${model.label} · ${model.sizeGb} GB'.toUpperCase(), style: muted),
                    const SizedBox(height: 4),
                    Text(
                      'Three things to know',
                      style: scriptureStyle(context)
                          .copyWith(fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    _Step(
                      1,
                      '${model.label} is a Google model. Berea keeps an unchanged copy on its own '
                      'release and checks its fingerprint after download.',
                    ),
                    const _Step(
                      2,
                      'By downloading or using it, you agree to the Gemma Terms of Use.',
                    ),
                    const _Step(3, gemmaUseRestriction),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${model.notice}', style: muted),
                    ),
                    const SizedBox(height: 8),
                    const _TextTile('Gemma Terms of Use', gemmaTermsAsset),
                    const _TextTile('Gemma Prohibited Use Policy', gemmaPolicyAsset),
                    const SizedBox(height: 8),
                    Text(
                      'Its answers can be wrong, so check them against the verses they cite.',
                      style: muted,
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          wifiOnly ? 'Agree and download on Wi-Fi' : 'Agree and download',
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step(this.n, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: _stepSize / 2,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text('$n', style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
