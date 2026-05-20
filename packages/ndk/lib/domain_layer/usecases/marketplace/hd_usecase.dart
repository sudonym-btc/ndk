import '../accounts/accounts.dart';

abstract class MarketplaceAccountIndexStore {
  Future<int?> loadLastAccountIndex(String pubkey);
  Future<void> saveLastAccountIndex(String pubkey, int accountIndex);
}

class MemoryMarketplaceAccountIndexStore
    implements MarketplaceAccountIndexStore {
  final Map<String, int> _indices = {};

  @override
  Future<int?> loadLastAccountIndex(String pubkey) async => _indices[pubkey];

  @override
  Future<void> saveLastAccountIndex(String pubkey, int accountIndex) async {
    _indices[pubkey] = accountIndex;
  }
}

class MarketplaceHdUsecase {
  final Accounts _accounts;
  final MarketplaceAccountIndexStore _store;

  MarketplaceHdUsecase({
    required Accounts accounts,
    MarketplaceAccountIndexStore? store,
  }) : _accounts = accounts,
       _store = store ?? MemoryMarketplaceAccountIndexStore();

  Future<int> getNextAccountIndex({
    String? pubkey,
    int firstIndex = 1,
    Future<bool> Function(int accountIndex)? isIndexUsed,
  }) async {
    final owner = pubkey ?? _accounts.getPublicKey();
    if (owner == null || owner.isEmpty) {
      throw StateError('Cannot allocate a marketplace account index');
    }

    var candidate =
        (await _store.loadLastAccountIndex(owner)) ?? firstIndex - 1;
    while (true) {
      candidate++;
      final used = await isIndexUsed?.call(candidate) ?? false;
      if (!used) {
        await _store.saveLastAccountIndex(owner, candidate);
        return candidate;
      }
    }
  }

  Future<void> rememberAccountIndex({
    String? pubkey,
    required int accountIndex,
  }) async {
    final owner = pubkey ?? _accounts.getPublicKey();
    if (owner == null || owner.isEmpty) {
      throw StateError('Cannot remember a marketplace account index');
    }
    final current = await _store.loadLastAccountIndex(owner);
    if (current == null || accountIndex > current) {
      await _store.saveLastAccountIndex(owner, accountIndex);
    }
  }
}
