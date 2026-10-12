import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// A dataset Berea ships or can download, with the licence it is used under.
class DataSource {
  final String name;
  final String licence;
  final String credit;
  const DataSource(this.name, this.licence, this.credit);
}

const builtInSources = [
  DataSource('Berean Standard Bible', 'Public domain (CC0)', 'bereanbible.com'),
  DataSource('King James Version', 'Public domain', 'via scrollmapper/bible_databases'),
  DataSource('World English Bible', 'Public domain', 'ebible.org'),
  DataSource(
    'STEPBible TAHOT, TAGNT, TBESH and TBESG',
    'CC BY 4.0',
    'Tyndale House, Cambridge, www.STEPBible.org',
  ),
  DataSource('Cross references', 'CC BY', 'OpenBible.info'),
];

const downloadableSources = [
  DataSource(
    'STEPBible TFLSJ (full Greek lexicon pack)',
    'CC BY 4.0',
    'Tyndale House, Cambridge, www.STEPBible.org',
  ),
  DataSource(
    'Kokoro-82M voice model and the Heart and Michael voices (voice pack)',
    'Apache-2.0',
    'hexgrad/Kokoro-82M; half-precision ONNX export with durations by onnx-community',
  ),
  DataSource(
    'CMU Pronouncing Dictionary (voice pack)',
    'BSD-style licence. Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved.',
    'cmusphinx/cmudict',
  ),
];

/// Libraries the voice runs on, compiled into the app.
const voiceLibraries = [
  DataSource('ONNX Runtime', 'MIT', 'Microsoft, via flutter_onnxruntime (MIT) by MASIC AI'),
  DataSource('audioplayers', 'MIT', 'Blue Fire'),
];

/// Full notices for what the voice pack carries and what the app links for it, shown on the
/// licence page beside every Dart package's own.
const _bundledNotices = [
  ('CMU Pronouncing Dictionary', 'assets/licenses/cmudict-LICENSE.txt'),
  ('Kokoro-82M voice model and voices', 'assets/licenses/apache-2.0.txt'),
  ('ONNX Runtime', 'assets/licenses/onnxruntime-LICENSE.txt'),
  ('ONNX Runtime third party notices', 'assets/licenses/onnxruntime-ThirdPartyNotices.txt'),
];

void registerBundledLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, asset) in _bundledNotices) {
      yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString(asset));
    }
  });
}

/// Every dataset in the app or offered for download, with its licence and who to credit.
class AttributionsScreen extends StatelessWidget {
  const AttributionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Licences and sources')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            children: [
              const _Heading('Built in'),
              for (final s in builtInSources) _SourceTile(s.name, s.credit, s.licence),
              const _Heading('Optional downloads'),
              for (final s in downloadableSources) _SourceTile(s.name, s.credit, s.licence),
              for (final m in commentaryModules)
                _SourceTile(m.title, '${m.author}. ${m.source} ${m.id}', m.licence),
              const _Heading('Voice libraries'),
              for (final s in voiceLibraries) _SourceTile(s.name, s.credit, s.licence),
              const _Heading('Berea'),
              const _SourceTile('Berea app and harness', 'github.com/CalvinMagezi/berea', 'MIT'),
              ListTile(
                title: const Text('All software licences'),
                subtitle: const Text('The full text of every licence and notice'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(context: context, applicationName: 'Berea'),
              ),
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
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _SourceTile extends StatelessWidget {
  final String name;
  final String credit;
  final String licence;
  const _SourceTile(this.name, this.credit, this.licence);

  @override
  Widget build(BuildContext context) =>
      ListTile(title: Text(name), subtitle: Text('$credit\n$licence'), isThreeLine: true);
}
