import 'dart:async';

import '../../entities/filter.dart';
import '../../entities/inbox/inbox_message.dart';
import '../../entities/inbox/inbox_thread.dart';
import '../../entities/nip_01_event.dart';
import '../../entities/request_response.dart';
import '../../repositories/event_signer.dart';
import '../accounts/accounts.dart';
import '../gift_wrap/gift_wrap.dart';
import '../requests/requests.dart';

class Inbox {
  final Requests _requests;
  final GiftWrap _giftWrap;
  final Accounts _accounts;
  final InboxParser _parser;
  final Map<String, InboxThread> _threads = {};
  final StreamController<InboxThread> _threadController =
      StreamController<InboxThread>.broadcast();

  Inbox({
    required Requests requests,
    required GiftWrap giftWrap,
    required Accounts accounts,
    InboxParser? parser,
  })  : _requests = requests,
        _giftWrap = giftWrap,
        _accounts = accounts,
        _parser = parser ?? InboxParser();

  Stream<InboxThread> get threadStream => _threadController.stream;
  Map<String, InboxThread> get threads => Map.unmodifiable(_threads);

  static List<String> normalizeParticipants(Iterable<String> participants) =>
      normalizeInboxParticipants(participants);

  static String threadIdentifier({
    required Iterable<String> participants,
    String conversationTag = '',
  }) =>
      inboxThreadId(
        participants: participants,
        conversationTag: conversationTag,
      );

  InboxThread ensureThread({
    required Iterable<String> participants,
    String conversationTag = '',
  }) {
    final id = threadIdentifier(
      participants: participants,
      conversationTag: conversationTag,
    );
    final existing = _threads[id];
    if (existing != null) return existing;
    final created = InboxThread(
      id: id,
      participants: participants,
      conversationTag: conversationTag.trim(),
    );
    _threads[id] = created;
    _threadController.add(created);
    return created;
  }

  InboxMessage processRumor(Nip01Event rumor, {Nip01Event? giftWrap}) {
    final message = _parser.parseRumor(rumor, giftWrap: giftWrap);
    final thread = ensureThread(
      participants: message.participants,
      conversationTag: message.conversationTag ?? '',
    );
    thread.add(message);
    return message;
  }

  Future<InboxMessage?> processGiftWrap(
    Nip01Event giftWrap, {
    EventSigner? customSigner,
  }) async {
    final rumor = await _giftWrap.fromGiftWrap(
      giftWrap: giftWrap,
      customSigner: customSigner,
    );
    return processRumor(rumor, giftWrap: giftWrap);
  }

  NdkResponse subscribeGiftWraps({
    String? pubkey,
    EventSigner? customSigner,
    Iterable<String>? explicitRelays,
    int limit = 200,
    bool cacheRead = true,
    bool cacheWrite = true,
  }) {
    final recipient =
        pubkey ?? customSigner?.getPublicKey() ?? _accounts.getPublicKey();
    if (recipient == null || recipient.isEmpty) {
      throw StateError('Cannot subscribe to inbox without a recipient pubkey');
    }

    final response = _requests.subscription(
      name: 'inbox-gift-wraps',
      filter: Filter(
        kinds: const [InboxKinds.giftWrap],
        pTags: [recipient],
        limit: limit,
      ),
      explicitRelays: explicitRelays,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
    );

    response.stream.listen((giftWrap) {
      processGiftWrap(giftWrap, customSigner: customSigner);
    });
    return response;
  }

  Future<List<InboxMessage>> pullGiftWraps({
    String? pubkey,
    EventSigner? customSigner,
    Iterable<String>? explicitRelays,
    int limit = 200,
    Duration? timeout,
    bool cacheRead = true,
    bool cacheWrite = true,
  }) async {
    final recipient =
        pubkey ?? customSigner?.getPublicKey() ?? _accounts.getPublicKey();
    if (recipient == null || recipient.isEmpty) {
      throw StateError('Cannot pull inbox without a recipient pubkey');
    }

    final response = _requests.query(
      name: 'inbox-gift-wraps',
      filter: Filter(
        kinds: const [InboxKinds.giftWrap],
        pTags: [recipient],
        limit: limit,
      ),
      explicitRelays: explicitRelays,
      timeout: timeout,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
    );

    final messages = <InboxMessage>[];
    await for (final giftWrap in response.stream) {
      final message = await processGiftWrap(
        giftWrap,
        customSigner: customSigner,
      );
      if (message != null) messages.add(message);
    }
    return messages;
  }

  Future<void> close() async {
    await _threadController.close();
  }
}
