import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'order.dart';

/// Groups all marketplace order events for one trade and participant set.
class MarketplaceOrderGroup {
  final List<MarketplaceOrder> orders;
  final bool confirmedCommitted;

  const MarketplaceOrderGroup({
    this.orders = const [],
    this.confirmedCommitted = false,
  });

  factory MarketplaceOrderGroup.fromOrder(MarketplaceOrder order) {
    return MarketplaceOrderGroup(orders: [order]);
  }

  MarketplaceOrderGroup copyWith({
    List<MarketplaceOrder>? orders,
    bool? confirmedCommitted,
  }) {
    return MarketplaceOrderGroup(
      orders: orders ?? this.orders,
      confirmedCommitted: confirmedCommitted ?? this.confirmedCommitted,
    );
  }

  MarketplaceOrderGroup addOrder(MarketplaceOrder order) {
    if (orders.isNotEmpty && !participantSet.contains(order.pubKey)) {
      return this;
    }
    final updated = orders.where((e) => e.pubKey != order.pubKey).toList()
      ..add(order);
    return copyWith(orders: updated);
  }

  Set<String> get participantSet {
    final result = <String>{};
    for (final order in orders) {
      result.add(order.pubKey);
      result.addAll(order.pTags);
    }
    return result;
  }

  static List<String> normalizeParticipants(Iterable<String> participants) =>
      (participants.where((pubkey) => pubkey.isNotEmpty).toSet().toList()
        ..sort());

  static String groupIdForParticipants({
    required String tradeId,
    required Iterable<String> participants,
  }) {
    final preimage = jsonEncode([
      normalizeParticipants(participants),
      tradeId.trim(),
    ]);
    return sha256.convert(utf8.encode(preimage)).toString();
  }

  static String groupIdFromOrder(MarketplaceOrder order) {
    final tradeId = order.tradeId ?? order.id;
    return groupIdForParticipants(
      tradeId: tradeId,
      participants: {order.pubKey, ...order.pTags},
    );
  }

  String get groupId => groupIdForParticipants(
        tradeId: tradeId,
        participants: participantSet,
      );

  MarketplaceOrder? get sellerOrder {
    if (orders.isEmpty) return null;
    final seller = sellerPubkey;
    return _lastWhereOrNull((order) => order.pubKey == seller);
  }

  MarketplaceOrder? get buyerOrder {
    if (orders.isEmpty) return null;
    final seller = sellerPubkey;
    final escrow = escrowPubkey;
    return _lastWhereOrNull(
      (order) => order.pubKey != seller && order.pubKey != escrow,
    );
  }

  MarketplaceOrder? get escrowOrder {
    final escrow = escrowPubkey;
    if (escrow == null || escrow == sellerPubkey) return null;
    return _lastWhereOrNull((order) => order.pubKey == escrow);
  }

  String get tradeId {
    return orders.map((order) => order.tradeId).whereType<String>().first;
  }

  String get listingAnchor {
    for (final order in orders) {
      final anchor = order.listingAnchor;
      if (anchor != null && anchor.isNotEmpty) return anchor;
    }
    throw StateError('No order in group carries a listing anchor');
  }

  String get sellerPubkey => pubkeyFromAddressableAnchor(listingAnchor);

  String? get buyerPubkey => buyerOrder?.pubKey;

  String? get escrowPubkey {
    for (final order in orders) {
      final pubkey = order.participantPubkeyForRole('escrow');
      if (pubkey != null && pubkey.isNotEmpty) return pubkey;
    }
    return null;
  }

  DateTime? get start => _committedOrder?.parsedContent.start ?? _firstStart;

  DateTime? get end => _committedOrder?.parsedContent.end ?? _firstEnd;

  bool get cancelled => orders.any((order) => order.isCancel);

  bool get sellerCancelled => sellerOrder?.isCancel ?? false;

  bool get buyerCancelled => buyerOrder?.isCancel ?? false;

  bool get isActive =>
      !cancelled && orders.isNotEmpty && _committedOrder != null;

  bool get isConfirmed => sellerOrder?.isCommit ?? false;

  bool get hasCommitConfirmation =>
      (sellerOrder?.isCommit ?? false) || (escrowOrder?.isCommit ?? false);

  bool get isCompleted {
    final orderEnd = end;
    if (orderEnd == null) return false;
    return !cancelled && orderEnd.isBefore(DateTime.now().toUtc());
  }

  MarketplaceOrderStage get stage {
    if (cancelled) return MarketplaceOrderStage.cancel;
    if (_committedOrder != null) return MarketplaceOrderStage.commit;
    return MarketplaceOrderStage.negotiate;
  }

  MarketplaceOrder? get _committedOrder {
    for (final order in orders) {
      if (order.isCommit) return order;
    }
    return null;
  }

  DateTime? get _firstStart {
    for (final order in orders) {
      final start = order.parsedContent.start;
      if (start != null) return start;
    }
    return null;
  }

  DateTime? get _firstEnd {
    for (final order in orders) {
      final end = order.parsedContent.end;
      if (end != null) return end;
    }
    return null;
  }

  MarketplaceOrder? _lastWhereOrNull(bool Function(MarketplaceOrder) test) {
    MarketplaceOrder? match;
    for (final order in orders) {
      if (test(order)) match = order;
    }
    return match;
  }
}

Map<String, MarketplaceOrderGroup> groupMarketplaceOrders({
  required Iterable<MarketplaceOrder> orders,
}) {
  final groups = <String, MarketplaceOrderGroup>{};
  for (final order in orders) {
    final groupId = MarketplaceOrderGroup.groupIdFromOrder(order);
    groups[groupId] = groups[groupId]?.addOrder(order) ??
        MarketplaceOrderGroup.fromOrder(order);
  }
  return Map.unmodifiable(groups);
}

String pubkeyFromAddressableAnchor(String anchor) {
  final parts = anchor.split(':');
  if (parts.length < 3 || parts[1].isEmpty) {
    throw ArgumentError.value(anchor, 'anchor', 'Invalid addressable anchor');
  }
  return parts[1];
}
