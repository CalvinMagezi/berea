import 'package:flutter/material.dart';

import 'app_state.dart';
import 'brand/lamp_mark.dart';
import 'models.dart';
import 'setup_screen.dart';
import 'terms.dart';
import 'theme.dart';

const helperMarkSize = 48.0;
const _markScale = 0.62;
const _optionRadius = 14.0;
const _selectedBorder = 1.5;
const _sectionGap = 20.0;
const _labelSpacing = 1.2;
const _labelSize = 12.0;

/// The Berea mark in a Night circle, as on the Study button, in both themes.
class HelperMark extends StatelessWidget {
  final double size;
  const HelperMark({super.key, this.size = helperMarkSize});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(color: BereaColors.night, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: LampMark(size: size * _markScale, ink: BereaColors.linen, flame: BereaColors.goldDark),
  );
}

/// A small capitalised heading, as Study's sections use.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: _labelSize,
        letterSpacing: _labelSpacing,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

/// Study before there is a helper: what Study does, the choice of helper, and Keep reading.
/// This is where a helper download starts.
class HelperSetup extends StatefulWidget {
  final AppState state;
  final VoidCallback onKeepReading;
  const HelperSetup({super.key, required this.state, required this.onKeepReading});

  @override
  State<HelperSetup> createState() => _HelperSetupState();
}

class _HelperSetupState extends State<HelperSetup> {
  late EdgeModel _chosen = _suggested;

  EdgeModel get _suggested => recommendedModel(widget.state.deviceGb);

  /// The suggested helper first, then the rest in their usual order.
  List<EdgeModel> get _options => [_suggested, ...edgeModels.where((m) => m != _suggested)];

  Future<void> _download() async {
    final s = widget.state;
    final m = _chosen;
    if (!await confirmModelTerms(context, s, m)) return;
    await s.downloadModelFor(
      s.settings.copyWith(
        engine: EngineKind.device,
        deviceModelId: m.id,
        tier: recommendedTier(m, s.deviceGb),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final scheme = Theme.of(context).colorScheme;
    final failed = switch (s.helperState) {
      HelperFailed(:final reason) => reason,
      _ => null,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            const HelperMark(),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Ask Berea about the Bible',
                style: scriptureStyle(context).copyWith(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _Point(
          Icons.menu_book_outlined,
          'Ask about a passage, a word, or a question of life.',
        ),
        const _Point(
          Icons.check,
          'Every answer is checked against the Bible text before you see it.',
        ),
        _Point(Icons.lock_outline, 'It runs on this $deviceNoun. What you ask stays here.'),
        const SizedBox(height: _sectionGap),
        SectionLabel('First, a helper for this $deviceNoun'),
        for (final m in _options)
          _ModelOption(
            model: m,
            selected: m == _chosen,
            suggested: m == _suggested,
            onTap: () => setState(() => _chosen = m),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Download only on Wi-Fi'),
          value: s.wifiOnly,
          onChanged: (on) => s.setWifiOnly(on),
        ),
        if (failed != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(failed, style: TextStyle(color: scheme.error)),
          ),
        FilledButton(
          onPressed: _download,
          child: Text('${s.wifiOnly ? 'Download on Wi-Fi' : 'Download'} · ${_chosen.sizeGb} GB'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: widget.onKeepReading, child: const Text('Keep reading')),
        Text(
          'Everything else in Berea works without it.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: _labelSize, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Point(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 14),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _ModelOption extends StatelessWidget {
  final EdgeModel model;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;
  const _ModelOption({
    required this.model,
    required this.selected,
    required this.suggested,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_optionRadius),
          side: selected
              ? BorderSide(color: scheme.primary, width: _selectedBorder)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(_optionRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 10, 0),
                  child: Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                Expanded(child: _details(context, muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context, TextStyle muted) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Text(model.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (suggested) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(_optionRadius),
                ),
                child: Text('Suggested', style: TextStyle(fontSize: 11, color: scheme.surface)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text('${model.sizeGb} GB · ${model.summary}', style: muted),
      ],
    );
  }
}
