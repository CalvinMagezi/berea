import 'package:flutter/material.dart';

/// Asks before an action that cannot be taken back; true when the person confirms.
Future<bool> confirmAction(BuildContext context, String title, String body, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    ) ==
    true;
