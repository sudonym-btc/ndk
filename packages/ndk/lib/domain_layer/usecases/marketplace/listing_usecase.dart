import '../../entities/broadcast_response.dart';
import '../../entities/marketplace/listing.dart';
import '../../entities/relay_set.dart';
import '../../repositories/event_signer.dart';
import '../accounts/accounts.dart';
import '../broadcast/broadcast.dart';
import '../requests/requests.dart';
import 'marketplace_response.dart';

class MarketplaceListingUsecase {
  final Requests _requests;
  final Broadcast _broadcast;
  final Accounts _accounts;

  MarketplaceListingUsecase({
    required Requests requests,
    required Broadcast broadcast,
    required Accounts accounts,
  }) : _requests = requests,
       _broadcast = broadcast,
       _accounts = accounts;

  NdkBroadcastResponse create<T extends BaseListing>(
    T listing, {
    Iterable<String>? specificRelays,
    EventSigner? customSigner,
  }) {
    final signer = customSigner ?? _accounts.getLoggedAccount()?.signer;
    if (signer == null) {
      throw StateError('Cannot create marketplace listing without a signer');
    }

    final event = listing.pubKey.isEmpty
        ? listing.copyWithPubKey(signer.getPublicKey())
        : listing;
    return _broadcast.broadcast(
      nostrEvent: event,
      specificRelays: specificRelays,
      customSigner: signer,
    );
  }

  MarketplaceResponse<T> search<T extends BaseListing>(
    MarketplaceListingTags<T> values, {
    int? limit,
    RelaySet? relaySet,
    bool cacheRead = true,
    bool cacheWrite = true,
    Duration? timeout,
    Iterable<String>? explicitRelays,
    bool paginate = false,
  }) {
    final response = _requests.query(
      name: 'marketplace-listing-search',
      filter: values.toFilter(limit: limit),
      relaySet: relaySet,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
      timeout: timeout,
      explicitRelays: explicitRelays,
      paginate: paginate,
    );

    return MarketplaceResponse<T>(
      response.requestId,
      response.stream.map(values.fromEvent),
    );
  }
}
