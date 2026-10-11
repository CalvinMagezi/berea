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
