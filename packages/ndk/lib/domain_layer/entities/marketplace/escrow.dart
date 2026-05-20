import 'dart:convert';

import '../nip_01_event.dart';
import 'marketplace_constants.dart';

class EscrowPaymentForm {
  final String denomination;
  final String tokenTagId;
  final String? appId;

  const EscrowPaymentForm({
    required this.denomination,
    required this.tokenTagId,
    this.appId,
  });

  factory EscrowPaymentForm.fromTag(List<String> tag) {
    if (tag.length < 3 || tag.first != 'o') {
      throw FormatException('Invalid escrow payment form tag: $tag');
    }
    return EscrowPaymentForm(
      denomination: tag[1],
      tokenTagId: tag[2],
      appId: tag.length >= 4 ? tag[3] : null,
    );
  }
}

class MarketplaceEscrowMethod extends Nip01Event {
  MarketplaceEscrowMethod({
    required super.pubKey,
    required super.tags,
    super.content = '',
    super.createdAt,
    super.id,
    super.sig,
    super.validSig,
    super.sources,
  }) : super(kind: MarketplaceKinds.escrowMethod);

  MarketplaceEscrowMethod.fromEvent(Nip01Event event)
    : super(
        id: event.id,
        pubKey: event.pubKey,
        kind: event.kind,
        tags: event.tags,
        content: event.content,
        sig: event.sig,
        validSig: event.validSig,
        sources: event.sources,
        createdAt: event.createdAt,
      ) {
    if (event.kind != MarketplaceKinds.escrowMethod) {
      throw ArgumentError(
        'Event kind ${event.kind} is not an escrow method event',
      );
    }
  }

  List<String> get escrowPubkeys => getTags('p');
  List<String> get contractBytecodeHashes => getTags('c');

  List<EscrowPaymentForm> get paymentForms {
    return tags
        .where((tag) => tag.isNotEmpty && tag.first == 'o')
        .map(EscrowPaymentForm.fromTag)
        .toList(growable: false);
  }
}

class MarketplaceEscrowService extends Nip01Event {
  MarketplaceEscrowService({
    required super.pubKey,
    required super.tags,
    required super.content,
    super.createdAt,
    super.id,
    super.sig,
    super.validSig,
    super.sources,
  }) : super(kind: MarketplaceKinds.escrowService);

  MarketplaceEscrowService.fromEvent(Nip01Event event)
    : super(
        id: event.id,
        pubKey: event.pubKey,
        kind: event.kind,
        tags: event.tags,
        content: event.content,
        sig: event.sig,
        validSig: event.validSig,
        sources: event.sources,
        createdAt: event.createdAt,
      ) {
    if (event.kind != MarketplaceKinds.escrowService) {
      throw ArgumentError(
        'Event kind ${event.kind} is not an escrow service event',
      );
    }
  }

  Map<String, dynamic> get jsonContent {
    if (content.isEmpty) return const {};
    return Map<String, dynamic>.from(jsonDecode(content) as Map);
  }

  String? get serviceId => getDtag();
  String? get operatorPubkey => jsonContent['pubkey'] as String? ?? pubKey;
  String? get evmAddress => jsonContent['evmAddress'] as String?;
  String? get contractAddress => jsonContent['contractAddress'] as String?;
  String? get contractBytecodeHash =>
      jsonContent['contractBytecodeHash'] as String?;
  int? get chainId => jsonContent['chainId'] as int?;
  String? get type => jsonContent['type'] as String?;
  num? get feePercent => jsonContent['feePercent'] as num?;
}

class MarketplaceEscrowServiceSelected extends Nip01Event {
  MarketplaceEscrowServiceSelected({
    required super.pubKey,
    required super.tags,
    required super.content,
    super.createdAt,
    super.id,
    super.sig,
    super.validSig,
    super.sources,
  }) : super(kind: MarketplaceKinds.escrowServiceSelected);

  MarketplaceEscrowServiceSelected.fromEvent(Nip01Event event)
    : super(
        id: event.id,
        pubKey: event.pubKey,
        kind: event.kind,
        tags: event.tags,
        content: event.content,
        sig: event.sig,
        validSig: event.validSig,
        sources: event.sources,
        createdAt: event.createdAt,
      ) {
    if (event.kind != MarketplaceKinds.escrowServiceSelected) {
      throw ArgumentError(
        'Event kind ${event.kind} is not an escrow service selection event',
      );
    }
    if (getDtag() == null || getDtag()!.isEmpty) {
      throw const FormatException(
        'Escrow service selection events require a d tag',
      );
    }
  }

  Map<String, dynamic> get jsonContent {
    if (content.isEmpty) return const {};
    return Map<String, dynamic>.from(jsonDecode(content) as Map);
  }

  String get tradeId => getDtag()!;
  String? get listingAnchor => getFirstTag(MarketplaceTags.listingRef);
  String? get serviceId =>
      jsonContent['serviceId'] as String? ?? jsonContent['id'] as String?;
  String? get servicePubkey =>
      jsonContent['servicePubkey'] as String? ??
      jsonContent['pubkey'] as String?;
}
