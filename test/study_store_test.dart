import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('notes, highlights and saved studies round trip', () {
    final store = StudyStore(sqlite3.openInMemory());
    final john = bookById(43);
    final id = store.addNote(RefParser.parse('John 3:16-17').first, 'first note');
    store.updateNote(id, 'edited');
    expect(store.notes(book: john, chapter: 3).single.text, 'edited');
    expect(store.notes().single.ref.label, 'John 3:16-17');

    store.toggleHighlight(john, 3, 16);
    expect(store.highlights(john, 3), {16});
    store.toggleHighlight(john, 3, 16);
    expect(store.highlights(john, 3), isEmpty);

    final conv = store.createConversation('What does John 3:16 teach about the love of God?');
    store.addMessage(conv, 'user', 'What does John 3:16 teach?', const []);
    store.addMessage(
      conv,
      'assistant',
      'It teaches...',
      RefParser.parse('John 3:16 and Romans 5:8'),
    );
    final msgs = store.messages(conv);
    expect(msgs.length, 2);
    expect(msgs.last.refs.map((r) => r.label), ['John 3:16', 'Romans 5:8']);
    expect(store.conversations().single.messageCount, 2);

    store.deleteConversation(conv);
    store.deleteNote(id);
    expect(store.conversations(), isEmpty);
    expect(store.notes(), isEmpty);
  });
}
