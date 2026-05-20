import '../../../data_layer/models/nip_01_event_model.dart';
import '../../../shared/nips/nip01/helpers.dart';
import '../../entities/broadcast_response.dart';
import '../../entities/filter.dart';
import '../../entities/marketplace/listing.dart';
import '../../entities/marketplace/marketplace_amount.dart';
import '../../entities/marketplace/marketplace_constants.dart';
import '../../entities/marketplace/order.dart';
import '../../entities/marketplace/order_group.dart';
import '../../entities/nip_01_event.dart';
import '../../repositories/event_signer.dart';
import '../accounts/accounts.dart';
import '../broadcast/broadcast.dart';
import '../gift_wrap/gift_wrap.dart';
import '../requests/requests.dart';
import 'marketplace_response.dart';

class MarketplaceOrderPublishResult {
  final MarketplaceOrder order;
  final NdkBroadcastResponse? orderBroadcast;
  final List<Nip01Event> giftWraps;
  final List<NdkBroadcastResponse> giftWrapBroadcasts;

  const MarketplaceOrderPublishResult({
    required this.order,
    this.orderBroadcast,
    this.giftWraps = const [],
    this.giftWrapBroadcasts = const [],
  });
}

class MarketplaceOrderUsecase {
  final Requests _requests;
  final Broadcast _broadcast;
  final Accounts _accounts;
  final GiftWrap _giftWrap;

  MarketplaceOrderUsecase({
    required Requests requests,
    required Broadcast broadcast,
    required Accounts accounts,
    required GiftWrap giftWrap,
  })  : _requests = requests,
        _broadcast = broadcast,
        _accounts = accounts,
        _giftWrap = giftWrap;

  MarketplaceAmount quote(BaseListing listing, OrderProperties properties) {
    return quoteOrder(listing, properties);
  }

  MarketplaceOrder build(
    BaseListing listing,
    OrderProperties properties, {
    String pubKey = '',
  }) {
    final stage = properties.stage ??
        (properties.proof == null
            ? MarketplaceOrderStage.negotiate
            : MarketplaceOrderStage.commit);
    final amount = properties.amount ?? quote(listing, properties);
    final dTag = properties.dTag ?? Helpers.getSecureRandomHex(32);

    return MarketplaceOrder.create(
      pubKey: pubKey,
      dTag: dTag,
      listingAnchor: listing.anchor,
      participants: [
        MarketplaceParticipantTag.seller(listing.pubKey),
        ...properties.participants,
      ],
      extraTags: properties.extraTags,
      content: MarketplaceOrderContent(
        start: properties.start,
        end: properties.end,
        stage: stage,
        quantity: properties.quantity,
        amount: amount,
        recipient: properties.recipient,
        proof: properties.proof,
        commitAuthorization: properties.commitAuthorization,
        shippingOptions: properties.shippingOptions,
        charges: properties.charges,
        extraContent: properties.extraContent,
      ),
    );
  }

  Future<MarketplaceOrderPublishResult> create(
    BaseListing listing,
    OrderProperties properties, {
    Iterable<String>? specificRelays,
    EventSigner? customSigner,
    bool giftWrap = true,
    Iterable<String>? giftWrapRecipients,
    bool? broadcastOrder,
  }) async {
    final signer = customSigner ?? _accounts.getLoggedAccount()?.signer;
    if (signer == null) {
      throw StateError('Cannot create marketplace order without a signer');
    }

    final unsigned = build(listing, properties, pubKey: signer.getPublicKey());
    final signed = MarketplaceOrder.fromEvent(await signer.sign(unsigned));
    final shouldBroadcastOrder =
        broadcastOrder ?? signed.stage == MarketplaceOrderStage.commit;

    NdkBroadcastResponse? orderBroadcast;
    if (shouldBroadcastOrder) {
      signed.ensureCanBroadcast();
      orderBroadcast = _broadcast.broadcast(
        nostrEvent: signed,
        specificRelays: specificRelays,
        customSigner: signer,
      );
    }

    final wraps = <Nip01Event>[];
    final wrapBroadcasts = <NdkBroadcastResponse>[];
    if (giftWrap) {
      final recipients = <String>{
        ...?giftWrapRecipients,
        listing.pubKey,
        signer.getPublicKey(),
      }..removeWhere((pubkey) => pubkey.isEmpty);

      for (final recipient in recipients) {
        final rumor = await _giftWrap.createRumor(
          customPubkey: signer.getPublicKey(),
          kind: MarketplaceKinds.structuredMessage,
          content: Nip01EventModel.fromEntity(signed).toJsonString(),
          tags: [
            ['p', recipient],
            [MarketplaceTags.conversation, signed.tradeId ?? ''],
            [MarketplaceTags.listingRef, listing.anchor],
          ],
        );
        final wrapped = await _giftWrap.toGiftWrap(
          rumor: rumor,
          recipientPubkey: recipient,
          customSigner: signer,
        );
        wraps.add(wrapped);
        wrapBroadcasts.add(
          _broadcast.broadcast(
            nostrEvent: wrapped,
            specificRelays: specificRelays,
          ),
        );
      }
    }

    return MarketplaceOrderPublishResult(
      order: signed,
      orderBroadcast: orderBroadcast,
      giftWraps: wraps,
      giftWrapBroadcasts: wrapBroadcasts,
    );
  }

  MarketplaceResponse<MarketplaceOrder> queryByTradeId(
    String tradeId, {
    Duration? timeout,
    Iterable<String>? explicitRelays,
    bool cacheRead = true,
    bool cacheWrite = true,
    int? limit,
  }) {
    final response = _requests.query(
      name: 'marketplace-orders-by-trade',
      filter: Filter(
        kinds: const [MarketplaceKinds.order],
        dTags: [tradeId],
        limit: limit,
      ),
      timeout: timeout,
      explicitRelays: explicitRelays,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
    );
    return MarketplaceResponse(
      response.requestId,
      response.stream.map(MarketplaceOrder.fromEvent),
    );
  }

  MarketplaceResponse<MarketplaceOrder> queryByListing({
    required String listingAnchor,
    Duration? timeout,
    Iterable<String>? explicitRelays,
    bool cacheRead = true,
    bool cacheWrite = true,
    int? limit,
  }) {
    final response = _requests.query(
      name: 'marketplace-orders-by-listing',
      filter: Filter(
        kinds: const [MarketplaceKinds.order],
        aTags: [listingAnchor],
        limit: limit,
      ),
      timeout: timeout,
      explicitRelays: explicitRelays,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
    );
    return MarketplaceResponse(
      response.requestId,
      response.stream.map(MarketplaceOrder.fromEvent),
    );
  }

  MarketplaceResponse<MarketplaceOrder> subscribeByListing({
    required String listingAnchor,
    Iterable<String>? explicitRelays,
    bool cacheRead = false,
    bool cacheWrite = false,
    int? limit,
  }) {
    final response = _requests.subscription(
      name: 'marketplace-orders-by-listing',
      filter: Filter(
        kinds: const [MarketplaceKinds.order],
        aTags: [listingAnchor],
        limit: limit,
      ),
      explicitRelays: explicitRelays,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
    );
    return MarketplaceResponse(
      response.requestId,
      response.stream.map(MarketplaceOrder.fromEvent),
    );
  }

  Map<String, MarketplaceOrderGroup> group(
    Iterable<MarketplaceOrder> orders,
  ) {
    return groupMarketplaceOrders(orders: orders);
  }
}
