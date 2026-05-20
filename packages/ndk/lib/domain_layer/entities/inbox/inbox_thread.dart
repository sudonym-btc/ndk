import 'inbox_message.dart';

class InboxThreadState {
  final String id;
  final String conversationTag;
  final List<String> participants;
  final List<InboxMessage> messages;
  final Map<String, int> seenUntil;

  const InboxThreadState({
    required this.id,
    required this.conversationTag,
    required this.participants,
    required this.messages,
    this.seenUntil = const {},
  });

  List<InboxMessage> get readableMessages => messages
      .where((message) => !message.isSeenStatus)
      .toList(growable: false);

  int unreadCount(String pubkey) {
    final seen = seenUntil[pubkey] ?? 0;
    return readableMessages
        .where((message) => message.pubKey != pubkey)
        .where((message) => message.createdAt > seen)
        .length;
  }

  bool allCounterpartiesReadLatestFrom(String pubkey) {
    final latest = readableMessages
        .where((message) => message.pubKey == pubkey)
        .map((message) => message.createdAt)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (latest == 0) return false;
    final counterparties = participants.where((p) => p != pubkey);
    return counterparties.every((p) => (seenUntil[p] ?? 0) >= latest);
  }
}

class InboxThread {
  final String id;
  final String conversationTag;
  final Set<String> _participants;
  final Map<String, int> _seenUntil = {};
  final List<InboxMessage> _messages = [];
  final Set<String> _messageIds = {};

  InboxThread({
    required this.id,
    required Iterable<String> participants,
    this.conversationTag = '',
  }) : _participants = normalizeInboxParticipants(participants).toSet();

  List<InboxMessage> get messages => List.unmodifiable(_messages);
  List<String> get participants =>
      List.unmodifiable(normalizeInboxParticipants(_participants));
  Map<String, int> get seenUntil => Map.unmodifiable(_seenUntil);

  InboxThreadState get state => InboxThreadState(
        id: id,
        conversationTag: conversationTag,
        participants: participants,
        messages: messages,
        seenUntil: seenUntil,
      );

  bool add(InboxMessage message) {
    if (!_messageIds.add(message.id)) return false;
    _participants.addAll(message.participants);

    final seenUntil = message.seenUntil;
    if (seenUntil != null) {
      final existing = _seenUntil[message.pubKey] ?? 0;
      if (seenUntil > existing) _seenUntil[message.pubKey] = seenUntil;
    } else {
      var index = _messages.length;
      for (var i = 0; i < _messages.length; i++) {
        if (_messages[i].createdAt > message.createdAt) {
          index = i;
          break;
        }
      }
      _messages.insert(index, message);
    }
    return true;
  }
}
