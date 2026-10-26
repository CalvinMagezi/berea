class ChatMessage {
  final String role;
  final String content;
  const ChatMessage(this.role, this.content);
  const ChatMessage.system(this.content) : role = 'system';
  const ChatMessage.user(this.content) : role = 'user';
  const ChatMessage.assistant(this.content) : role = 'assistant';

  Map<String, String> toJson() => {'role': role, 'content': content};
}

abstract class LlmEngine {
  String get name;
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens});
}

/// An engine that can end a generation early. The stream then finishes with what was written so
/// far, so the answer keeps its partial text and the citation check still runs on it.
abstract interface class StoppableEngine {
  Future<void> stop();
}
