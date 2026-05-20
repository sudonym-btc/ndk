import 'dart:async';
import 'dart:convert';

import '../../../data_layer/models/nip_01_event_model.dart';
import '../../entities/filter.dart';
import '../../entities/marketplace/marketplace_constants.dart';
import '../../entities/marketplace/order.dart';
import '../../entities/nip_01_event.dart';
import '../../repositories/event_signer.dart';
import '../accounts/accounts.dart';
import '../gift_wrap/gift_wrap.dart';
import '../requests/requests.dart';
import 'marketplace_response.dart';

class MarketplaceOffer {
  final MarketplaceOrder order;
  final Nip01Event giftWrap;
  final Nip01Event rumor;

  const MarketplaceOffer({
    required this.order,
    required this.giftWrap,
    required this.rumor,
  });
}

class MarketplaceOffersUsecase {
  final Requests _requests;
  final GiftWrap _giftWrap;
  final Accounts _accounts;

  MarketplaceOffersUsecase({
    required Requests requests,
    required GiftWrap giftWrap,
    required Accounts accounts,
  }) : _requests = requests,
       _giftWrap = giftWrap,
       _accounts = accounts;

  MarketplaceResponse<MarketplaceOffer> list({
    String? pubkey,
    EventSigner? customSigner,
    Duration? timeout,
    Iterable<String>? explicitRelays,
    bool cacheRead = true,
    bool cacheWrite = true,
    int limit = 100,
    bool paginate = false,
  }) {
    final recipient =
        pubkey ?? customSigner?.getPublicKey() ?? _accounts.getPublicKey();
    if (recipient == null || recipient.isEmpty) {
      throw StateError('Cannot list marketplace offers without a recipient');
    }

    final response = _requests.query(
      name: 'marketplace-offers',
      filter: Filter(
        kinds: const [GiftWrap.kGiftWrapEventkind],
        pTags: [recipient],
        limit: limit,
      ),
      timeout: timeout,
      explicitRelays: explicitRelays,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
      paginate: paginate,
    );

    final controller = StreamController<MarketplaceOffer>();
    () async {
      await for (final giftWrap in response.stream) {
        try {
          final rumor = await _giftWrap.fromGiftWrap(
            giftWrap: giftWrap,
            customSigner: customSigner,
          );
          if (rumor.kind != MarketplaceKinds.structuredMessage) continue;
          final child = Nip01EventModel.fromJson(jsonDecode(rumor.content));
          if (child.kind != MarketplaceKinds.order) continue;
          controller.add(
            MarketplaceOffer(
              order: MarketplaceOrder.fromEvent(child),
              giftWrap: giftWrap,
              rumor: rumor,
            ),
          );
        } catch (_) {
          // Offers are best-effort: malformed or undecryptable wraps are skipped.
        }
      }
      await controller.close();
    }();

    return MarketplaceResponse(response.requestId, controller.stream);
  }
}
