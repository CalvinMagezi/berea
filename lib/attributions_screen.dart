import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

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
];

/// Native code shipped inside the app whose licence asks for a notice.
const bundledSoftware = [
  DataSource(
    'PDFium (reads PDF text for notebooks)',
    'BSD 3-Clause and Apache 2.0, with FreeType (FreeType License), libjpeg-turbo, OpenJPEG, '
        'Little CMS, libpng, zlib, Abseil and ICU under their own permissive licences',
    'The PDFium Authors; binaries by Benoit Blanchon (MIT) and pdfium_flutter by Takashi '
        'Kawasaki (MIT). Portions of this software are copyright The FreeType Project '
        '(www.freetype.org). All rights reserved. This software is based in part on the work of '
        'the Independent JPEG Group. Full texts are under Software licences below.',
  ),
];

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
              const _Heading('Berea'),
              const _SourceTile('Berea app and harness', 'github.com/CalvinMagezi/berea', 'MIT'),
              for (final s in bundledSoftware) _SourceTile(s.name, s.credit, s.licence),
              ListTile(
                title: const Text('Software licences'),
                subtitle: const Text('Full licence texts for the code and libraries in Berea'),
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
