import '../../entities/filter.dart';
import '../../entities/marketplace/escrow.dart';
import '../../entities/marketplace/marketplace_constants.dart';
import '../requests/requests.dart';

class MarketplaceEscrowMethodUsecase {
  final Requests _requests;

  MarketplaceEscrowMethodUsecase({required Requests requests})
    : _requests = requests;

  Future<MarketplaceEscrowMethod?> get({
    required String pubkey,
    Duration? timeout,
    Iterable<String>? explicitRelays,
    bool cacheRead = true,
    bool cacheWrite = true,
  }) async {
    final response = _requests.query(
      name: 'marketplace-escrow-method',
      filter: Filter(
        authors: [pubkey],
        kinds: const [MarketplaceKinds.escrowMethod],
        limit: 1,
      ),
      timeout: timeout,
      explicitRelays: explicitRelays,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
    );
    final events = await response.future;
    if (events.isEmpty) return null;
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return MarketplaceEscrowMethod.fromEvent(events.first);
  }
}

class MarketplaceEscrowUsecase {
  final Requests _requests;

  MarketplaceEscrowUsecase({required Requests requests}) : _requests = requests;

  Future<List<MarketplaceEscrowService>> get({
    required MarketplaceEscrowMethod sellerMethod,
    MarketplaceEscrowMethod? buyerMethod,
    Duration? timeout,
    Iterable<String>? explicitRelays,
    bool cacheRead = true,
    bool cacheWrite = true,
  }) async {
    final trustedEscrows = _intersectionOrFallback(
      sellerMethod.escrowPubkeys,
      buyerMethod?.escrowPubkeys,
    );
    if (trustedEscrows.isEmpty) return const [];

    final acceptedContracts = _intersectionOrFallback(
      sellerMethod.contractBytecodeHashes,
      buyerMethod?.contractBytecodeHashes,
    );

    final response = _requests.query(
      name: 'marketplace-escrow-services',
      filter: Filter(
        authors: trustedEscrows.toList(),
        kinds: const [MarketplaceKinds.escrowService],
      ),
      timeout: timeout,
      explicitRelays: explicitRelays,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
    );

    final services = [
      for (final event in await response.future)
        MarketplaceEscrowService.fromEvent(event),
    ];

    return services
        .where((service) {
          if (acceptedContracts.isEmpty) return true;
          final contractHash = service.contractBytecodeHash;
          return contractHash != null &&
              acceptedContracts.contains(contractHash);
        })
        .toList(growable: false);
  }

  Set<String> _intersectionOrFallback(
    Iterable<String> sellerValues,
    Iterable<String>? buyerValues,
  ) {
    final seller = sellerValues.toSet();
    final buyer = buyerValues?.toSet();
    if (buyer == null || buyer.isEmpty) return seller;
    return seller.intersection(buyer);
  }
}
