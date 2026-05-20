import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../data_layer/models/nip_01_event_model.dart';
import '../nip_01_event.dart';

typedef InboxChildParser = Nip01Event Function(Nip01Event event);

class InboxKinds {
  static const int privateDirectMessage = 14;
  static const int structuredMessage = 1327;
  static const int seenStatus = 16;
  static const int giftWrap = 1059;
  static const int dmRelays = 10050;
  static const int receivedHeartbeat = 10017;
}

class InboxTags {
  static const String conversation = 'conversation';
}

class InboxMessage {
  final Nip01Event rumor;
  final Nip01Event? child;
  final Nip01Event? giftWrap;

  const InboxMessage({required this.rumor, this.child, this.giftWrap});

  String get id => rumor.id;
  int get createdAt => rumor.createdAt;
  String get pubKey => rumor.pubKey;
  int get kind => rumor.kind;
  String get content => rumor.content;
  List<List<String>> get tags => rumor.tags;
  String? get conversationTag => rumor.getFirstTag(InboxTags.conversation);
  bool get isText =>
      child == null && rumor.kind == InboxKinds.privateDirectMessage;
  bool get isStructured => child != null;
  bool get isSeenStatus => rumor.kind == InboxKinds.seenStatus;
  List<String> get participants => [rumor.pubKey, ...rumor.pTags];

  int? get seenUntil {
    if (!isSeenStatus) return null;
    final raw = rumor.getFirstTag('seen_until') ??
        rumor.getFirstTag('seenUntil') ??
        rumor.getFirstTag('until');
    return raw == null ? null : int.tryParse(raw);
  }
}

class InboxParser {
  final Map<int, InboxChildParser> _childParsers;
  final Set<int> _structuredKinds;

  InboxParser({
    Map<int, InboxChildParser> childParsers = const {},
    Iterable<int> structuredKinds = const [InboxKinds.structuredMessage],
  })  : _childParsers = Map.unmodifiable(childParsers),
        _structuredKinds = Set.unmodifiable(structuredKinds);

  InboxParser copyWith({
    Map<int, InboxChildParser> childParsers = const {},
    Iterable<int>? structuredKinds,
  }) {
    return InboxParser(
      childParsers: {..._childParsers, ...childParsers},
      structuredKinds: structuredKinds ?? _structuredKinds,
    );
  }

  InboxMessage parseRumor(Nip01Event rumor, {Nip01Event? giftWrap}) {
    return InboxMessage(
      rumor: rumor,
      giftWrap: giftWrap,
      child: parseChild(rumor),
    );
  }

  Nip01Event? parseChild(Nip01Event rumor) {
    final isStructured = _structuredKinds.contains(rumor.kind);
    if (!isStructured && rumor.kind != InboxKinds.privateDirectMessage) {
      return null;
    }

    try {
      final event = Nip01EventModel.fromJson(jsonDecode(rumor.content));
      final parser = _childParsers[event.kind];
      return parser != null ? parser(event) : event;
    } catch (_) {
      if (isStructured) {
        throw FormatException(
          'Malformed structured inbox message kind=${rumor.kind} id=${rumor.id}',
        );
      }
      return null;
    }
  }
}

List<String> normalizeInboxParticipants(Iterable<String> participants) =>
    (participants.where((pubkey) => pubkey.isNotEmpty).toSet().toList()
      ..sort());

String inboxThreadId({
  required Iterable<String> participants,
  String conversationTag = '',
}) {
  final preimage = jsonEncode([
    normalizeInboxParticipants(participants),
    conversationTag.trim(),
  ]);
  return sha256.convert(utf8.encode(preimage)).toString();
}
