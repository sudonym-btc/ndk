import '../../entities/broadcast_response.dart';
import '../../entities/filter.dart';
import '../../entities/marketplace/marketplace_constants.dart';
import '../../entities/marketplace/order.dart';
import '../../entities/marketplace/order_transition.dart';
import '../../repositories/event_signer.dart';
import '../accounts/accounts.dart';
import '../broadcast/broadcast.dart';
import '../requests/requests.dart';
import 'marketplace_response.dart';

class MarketplaceOrderTransitionPublishResult {
  final MarketplaceOrderTransition transition;
  final NdkBroadcastResponse broadcast;

  const MarketplaceOrderTransitionPublishResult({
    required this.transition,
    required this.broadcast,
  });
}

class MarketplaceOrderTransitionsUsecase {
  final Requests _requests;
  final Broadcast _broadcast;
  final Accounts _accounts;

  MarketplaceOrderTransitionsUsecase({
    required Requests requests,
    required Broadcast broadcast,
    required Accounts accounts,
  })  : _requests = requests,
        _broadcast = broadcast,
        _accounts = accounts;

  Future<MarketplaceOrderTransitionPublishResult> record({
    required MarketplaceOrder order,
    required MarketplaceOrderTransitionType transitionType,
    required MarketplaceOrderStage fromStage,
    required MarketplaceOrderStage toStage,
    EventSigner? customSigner,
    Iterable<String>? specificRelays,
    String? commitTermsHash,
    String? reason,
    Map<String, dynamic>? updatedFields,
    String? prevTransitionId,
  }) async {
    final signer = customSigner ?? _accounts.getLoggedAccount()?.signer;
    if (signer == null) {
      throw StateError(
        'Cannot record marketplace order transition without a signer',
      );
    }

    final tradeId = order.tradeId ?? '';
    final effectivePrevTransitionId = prevTransitionId ??
        await _resolvePreviousTransitionId(
          tradeId: tradeId,
          pubkey: signer.getPublicKey(),
        );
    final unsigned = MarketplaceOrderTransition.create(
      pubKey: signer.getPublicKey(),
      order: order,
      prevTransitionId: effectivePrevTransitionId,
      content: MarketplaceOrderTransitionContent(
        transitionType: transitionType,
        fromStage: fromStage,
        toStage: toStage,
        commitTermsHash: commitTermsHash ?? order.commitHash(),
        reason: reason,
        updatedFields: updatedFields,
      ),
    );
    final signed =
        MarketplaceOrderTransition.fromEvent(await signer.sign(unsigned));
    return MarketplaceOrderTransitionPublishResult(
      transition: signed,
      broadcast: _broadcast.broadcast(
        nostrEvent: signed,
        specificRelays: specificRelays,
      ),
    );
  }

  MarketplaceResponse<MarketplaceOrderTransition> queryByTradeId(
    String tradeId, {
    Duration? timeout,
    Iterable<String>? explicitRelays,
    bool cacheRead = true,
    bool cacheWrite = true,
    int? limit,
  }) {
    final response = _requests.query(
      name: 'marketplace-order-transitions',
      filter: Filter(
        kinds: const [MarketplaceKinds.orderTransition],
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
      response.stream.map(MarketplaceOrderTransition.fromEvent),
    );
  }

  MarketplaceResponse<MarketplaceOrderTransition> subscribeByTradeId(
    String tradeId, {
    Iterable<String>? explicitRelays,
    bool cacheRead = false,
    bool cacheWrite = false,
    int? limit,
  }) {
    final response = _requests.subscription(
      name: 'marketplace-order-transitions',
      filter: Filter(
        kinds: const [MarketplaceKinds.orderTransition],
        dTags: [tradeId],
        limit: limit,
      ),
      explicitRelays: explicitRelays,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
    );
    return MarketplaceResponse(
      response.requestId,
      response.stream.map(MarketplaceOrderTransition.fromEvent),
    );
  }

  Future<String?> _resolvePreviousTransitionId({
    required String tradeId,
    required String pubkey,
  }) async {
    if (tradeId.isEmpty) return null;

    final existing = await queryByTradeId(tradeId)
        .stream
        .where((transition) => transition.pubKey == pubkey)
        .toList();
    if (existing.isEmpty) return null;

    final chain = resolveMarketplaceTransitionChain(existing);
    if (!chain.validation.isValid) {
      throw StateError(
        'Cannot append marketplace order transition: existing transition '
        'chain is invalid (${chain.validation.reason})',
      );
    }

    return chain.transitions.last.id;
  }
}
