import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:test/test.dart';

import '../../mocks/mock_event_verifier.dart';

void main() {
  const buyerPubkey =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const sellerPubkey =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  Ndk buildNdk({InboxParser? inboxParser}) {
    return Ndk(
      NdkConfig(
        eventVerifier: MockEventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: const [],
        inboxParser: inboxParser,
      ),
    );
  }

  Nip01Event textMessage({
    required String id,
    required String sender,
    required List<String> recipients,
    required int createdAt,
    String conversationTag = 'trade-1',
  }) {
    return Nip01Event(
      id: id,
      pubKey: sender,
      kind: InboxKinds.privateDirectMessage,
      tags: [
        for (final recipient in recipients) ['p', recipient],
        [InboxTags.conversation, conversationTag],
      ],
      content: 'hello-$id',
      createdAt: createdAt,
    );
  }

  group('inbox threads', () {
    test('groups same participants and conversation tag into one thread', () {
      final ndk = buildNdk();
      final expectedId = Inbox.threadIdentifier(
        participants: const [buyerPubkey, sellerPubkey],
        conversationTag: 'trade-1',
      );

      ndk.inbox.processRumor(
        textMessage(
          id: 'm-1',
          sender: buyerPubkey,
          recipients: const [sellerPubkey],
          createdAt: 100,
        ),
      );
      ndk.inbox.processRumor(
        textMessage(
          id: 'm-2',
          sender: sellerPubkey,
          recipients: const [buyerPubkey],
          createdAt: 101,
        ),
      );

      expect(ndk.inbox.threads.length, 1);
      expect(ndk.inbox.threads.containsKey(expectedId), isTrue);
      expect(
        ndk.inbox.threads[expectedId]!.state.readableMessages,
        hasLength(2),
      );
    });

    test('creates a new thread when conversation tag changes', () {
      final ndk = buildNdk();

      ndk.inbox.processRumor(
        textMessage(
          id: 'm-1',
          sender: buyerPubkey,
          recipients: const [sellerPubkey],
          conversationTag: 'trade-x',
          createdAt: 100,
        ),
      );
      ndk.inbox.processRumor(
        textMessage(
          id: 'm-2',
          sender: buyerPubkey,
          recipients: const [sellerPubkey],
          conversationTag: 'trade-y',
          createdAt: 101,
        ),
      );

      expect(ndk.inbox.threads.length, 2);
    });

    test('parses structured child events with caller-provided parsers', () {
      const structuredChildKind = 30001;
      final ndk = buildNdk(
        inboxParser: InboxParser(
          childParsers: {
            structuredChildKind: (event) => Nip01Event(
                  id: event.id,
                  pubKey: event.pubKey,
                  kind: event.kind,
                  tags: event.tags,
                  content: 'parsed:${event.content}',
                  createdAt: event.createdAt,
                ),
          },
        ),
      );
      final child = Nip01Event(
        id: 'child-1',
        pubKey: buyerPubkey,
        kind: structuredChildKind,
        tags: const [
          ['d', 'trade-1'],
        ],
        content: 'child-payload',
        createdAt: 99,
      );

      final message = ndk.inbox.processRumor(
        Nip01Event(
          id: 'structured-1',
          pubKey: buyerPubkey,
          kind: InboxKinds.structuredMessage,
          tags: const [
            ['p', sellerPubkey],
            [InboxTags.conversation, 'trade-1'],
          ],
          content: Nip01EventModel.fromEntity(child).toJsonString(),
          createdAt: 100,
        ),
      );

      expect(message.child, isA<Nip01Event>());
      expect(message.child!.kind, structuredChildKind);
      expect(message.child!.content, 'parsed:child-payload');
    });

    test('tracks seen receipts without adding them to readable messages', () {
      final ndk = buildNdk();
      final threadId = Inbox.threadIdentifier(
        participants: const [buyerPubkey, sellerPubkey],
        conversationTag: 'trade-1',
      );

      ndk.inbox.processRumor(
        textMessage(
          id: 'm-1',
          sender: sellerPubkey,
          recipients: const [buyerPubkey],
          createdAt: 100,
        ),
      );
      expect(ndk.inbox.threads[threadId]!.state.unreadCount(buyerPubkey), 1);

      ndk.inbox.processRumor(
        Nip01Event(
          id: 'seen-1',
          pubKey: buyerPubkey,
          kind: InboxKinds.seenStatus,
          tags: const [
            ['p', sellerPubkey],
            [InboxTags.conversation, 'trade-1'],
            ['seen_until', '100'],
          ],
          content: '',
          createdAt: 101,
        ),
      );

      final state = ndk.inbox.threads[threadId]!.state;
      expect(state.readableMessages, hasLength(1));
      expect(state.unreadCount(buyerPubkey), 0);
      expect(state.seenUntil[buyerPubkey], 100);
    });

    test(
      'unwraps giftwraps and routes the inner rumor into a thread',
      () async {
        final ndk = buildNdk();
        const senderPrivateKey =
            '556f19cc663fa7ff6840e6b6dc4ab244e8e952161f116b06d04c76cba659b980';
        const recipientPrivateKey =
            '1714ff69753ae70a91d6e1989cb1ee859b10e98239c61d28bcb0577d8d626b74';
        final senderPubkey = Bip340.getPublicKey(senderPrivateKey);
        final recipientPubkey = Bip340.getPublicKey(recipientPrivateKey);
        final senderSigner = Bip340EventSigner(
          privateKey: senderPrivateKey,
          publicKey: senderPubkey,
        );
        final recipientSigner = Bip340EventSigner(
          privateKey: recipientPrivateKey,
          publicKey: recipientPubkey,
        );
        final rumor = await ndk.giftWrap.createRumor(
          customPubkey: senderPubkey,
          kind: InboxKinds.privateDirectMessage,
          content: 'wrapped hello',
          tags: [
            ['p', recipientPubkey],
            [InboxTags.conversation, 'trade-1'],
          ],
        );
        final giftWrap = await ndk.giftWrap.toGiftWrap(
          rumor: rumor,
          recipientPubkey: recipientPubkey,
          customSigner: senderSigner,
        );

        final message = await ndk.inbox.processGiftWrap(
          giftWrap,
          customSigner: recipientSigner,
        );
        final threadId = Inbox.threadIdentifier(
          participants: [senderPubkey, recipientPubkey],
          conversationTag: 'trade-1',
        );

        expect(message?.content, 'wrapped hello');
        expect(
          ndk.inbox.threads[threadId]?.state.readableMessages,
          hasLength(1),
        );
      },
    );
  });
}
