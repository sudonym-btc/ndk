import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../data_layer/models/nip_01_event_model.dart';
import '../nip_01_event.dart';
import 'listing.dart';
import 'marketplace_amount.dart';
import 'marketplace_constants.dart';

enum MarketplaceOrderStage { negotiate, commit, cancel }

class MarketplaceParticipantTag {
  final String pubkey;
  final String relayHint;
  final String? role;

  const MarketplaceParticipantTag(
    this.pubkey, {
    this.relayHint = '',
    this.role,
  });

  const MarketplaceParticipantTag.seller(this.pubkey, {this.relayHint = ''})
    : role = 'seller';

  const MarketplaceParticipantTag.buyer(this.pubkey, {this.relayHint = ''})
    : role = 'buyer';

  const MarketplaceParticipantTag.escrow(this.pubkey, {this.relayHint = ''})
    : role = 'escrow';

  List<String> toTag() {
    return role == null
        ? ['p', pubkey, relayHint]
        : ['p', pubkey, relayHint, role!];
  }
}

class OrderShippingOptionSelection {
  final String optionAnchor;
  final String country;
  final String? region;
  final String? service;
  final MarketplaceAmount amount;

  const OrderShippingOptionSelection({
    required this.optionAnchor,
    required this.country,
    required this.amount,
    this.region,
    this.service,
  });

  factory OrderShippingOptionSelection.fromJson(Map<String, dynamic> json) {
    return OrderShippingOptionSelection(
      optionAnchor: json['optionAnchor'] as String,
      country: json['country'] as String,
      region: json['region'] as String?,
      service: json['service'] as String?,
      amount: MarketplaceAmount.fromJson(
        Map<String, dynamic>.from(json['amount'] as Map),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'optionAnchor': optionAnchor,
    'country': country,
    if (region != null) 'region': region,
    if (service != null) 'service': service,
    'amount': amount.toJson(),
  };
}

class OrderProperties {
  final String? dTag;
  final DateTime? start;
  final DateTime? end;
  final MarketplaceOrderStage? stage;
  final int quantity;
  final MarketplaceAmount? amount;
  final String? recipient;
  final Object? proof;
  final Object? commitAuthorization;
  final List<OrderShippingOptionSelection> shippingOptions;
  final List<MarketplaceCharge> charges;
  final List<MarketplaceParticipantTag> participants;
  final List<List<String>> extraTags;
  final Map<String, dynamic> extraContent;

  const OrderProperties({
    this.dTag,
    this.start,
    this.end,
    this.stage,
    this.quantity = 1,
    this.amount,
    this.recipient,
    this.proof,
    this.commitAuthorization,
    this.shippingOptions = const [],
    this.charges = const [],
    this.participants = const [],
    this.extraTags = const [],
    this.extraContent = const {},
  });
}

class MarketplaceOrderContent {
  final DateTime? start;
  final DateTime? end;
  final MarketplaceOrderStage stage;
  final int quantity;
  final MarketplaceAmount? amount;
  final String? recipient;
  final Object? proof;
  final Object? commitAuthorization;
  final List<OrderShippingOptionSelection> shippingOptions;
  final List<MarketplaceCharge> charges;
  final Map<String, dynamic> extraContent;

  const MarketplaceOrderContent({
    this.start,
    this.end,
    required this.stage,
    this.quantity = 1,
    this.amount,
    this.recipient,
    this.proof,
    this.commitAuthorization,
    this.shippingOptions = const [],
    this.charges = const [],
    this.extraContent = const {},
  });

  factory MarketplaceOrderContent.fromJson(Map<String, dynamic> json) {
    return MarketplaceOrderContent(
      start: json['start'] != null ? DateTime.parse(json['start']) : null,
      end: json['end'] != null ? DateTime.parse(json['end']) : null,
      stage: MarketplaceOrderStage.values.firstWhere(
        (stage) => stage.name == json['stage'],
      ),
      quantity: json['quantity'] as int? ?? 1,
      amount: json['amount'] != null
          ? MarketplaceAmount.fromJson(
              Map<String, dynamic>.from(json['amount'] as Map),
            )
          : null,
      recipient: json['recipient'] as String?,
      proof: json['proof'],
      commitAuthorization: json['commitAuthorization'],
      shippingOptions: [
        for (final item in (json['shippingOptions'] as List? ?? const []))
          OrderShippingOptionSelection.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
      ],
      charges: [
        for (final item in (json['charges'] as List? ?? const []))
          MarketplaceCharge.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      extraContent: Map<String, dynamic>.from(
        json['extraContent'] as Map? ?? const {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    if (start != null) 'start': start!.toUtc().toIso8601String(),
    if (end != null) 'end': end!.toUtc().toIso8601String(),
    'stage': stage.name,
    'quantity': quantity,
    if (amount != null) 'amount': amount!.toJson(),
    if (recipient != null) 'recipient': recipient,
    if (proof != null) 'proof': proof,
    if (commitAuthorization != null) 'commitAuthorization': commitAuthorization,
    if (shippingOptions.isNotEmpty)
      'shippingOptions': [
        for (final shippingOption in shippingOptions) shippingOption.toJson(),
      ],
    if (charges.isNotEmpty)
      'charges': [for (final charge in charges) charge.toJson()],
    if (extraContent.isNotEmpty) 'extraContent': extraContent,
  };

  Map<String, dynamic> committedJson() {
    final json = toJson();
    return {
      if (json.containsKey('start')) 'start': json['start'],
      if (json.containsKey('end')) 'end': json['end'],
      'quantity': json['quantity'],
      if (json.containsKey('amount')) 'amount': json['amount'],
      if (json.containsKey('recipient')) 'recipient': json['recipient'],
      if (json.containsKey('shippingOptions'))
        'shippingOptions': json['shippingOptions'],
      if (json.containsKey('charges')) 'charges': json['charges'],
    };
  }

  String commitHash() {
    return sha256
        .convert(utf8.encode(_canonicalJson(committedJson())))
        .toString();
  }
}

class MarketplaceOrder extends Nip01Event {
  MarketplaceOrder({
    super.id,
    required super.pubKey,
    required super.tags,
    required MarketplaceOrderContent orderContent,
    super.sig,
    super.validSig,
    super.sources,
    int? createdAt,
  }) : super(
         kind: MarketplaceKinds.order,
         content: jsonEncode(orderContent.toJson()),
         createdAt: createdAt ?? Nip01Event.secondsSinceEpoch(),
       );

  MarketplaceOrder._raw({
    required super.pubKey,
    required super.tags,
    required super.content,
    super.createdAt,
  }) : super(kind: MarketplaceKinds.order);

  MarketplaceOrder.fromEvent(Nip01Event event)
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
    if (event.kind != MarketplaceKinds.order) {
      throw ArgumentError(
        'Event kind ${event.kind} is not a marketplace order',
      );
    }
  }

  factory MarketplaceOrder.create({
    required String pubKey,
    required String dTag,
    required String listingAnchor,
    required MarketplaceOrderContent content,
    List<MarketplaceParticipantTag> participants = const [],
    List<List<String>> extraTags = const [],
    int? createdAt,
  }) {
    final eventCreatedAt = createdAt ?? Nip01Event.secondsSinceEpoch();
    return MarketplaceOrder(
      pubKey: pubKey,
      createdAt: eventCreatedAt,
      tags: [
        ['d', dTag],
        [MarketplaceTags.listingRef, listingAnchor],
        [MarketplaceTags.publishedAt, eventCreatedAt.toString()],
        for (final participant in participants) participant.toTag(),
        ...extraTags,
      ],
      orderContent: content,
    );
  }

  MarketplaceOrderContent get parsedContent {
    return MarketplaceOrderContent.fromJson(
      Map<String, dynamic>.from(jsonDecode(content) as Map),
    );
  }

  String? get tradeId => getDtag();
  String? get listingAnchor => getFirstTag(MarketplaceTags.listingRef);
  MarketplaceOrderStage get stage => parsedContent.stage;
  MarketplaceAmount? get amount => parsedContent.amount;

  String commitHash() => parsedContent.commitHash();

  MarketplaceOrder copyWithPubKey(String pubKey) {
    return MarketplaceOrder._raw(
      pubKey: pubKey,
      tags: tags,
      content: content,
      createdAt: createdAt,
    );
  }

  Nip01EventModel get model => Nip01EventModel.fromEntity(this);
}

MarketplaceAmount quoteOrder(BaseListing listing, OrderProperties properties) {
  var total = listing.cost(
    start: properties.start,
    end: properties.end,
    quantity: properties.quantity,
  );

  for (final shippingOption in properties.shippingOptions) {
    total += shippingOption.amount;
  }
  for (final charge in properties.charges) {
    total += charge.amount;
  }
  return total;
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) {
      return '${jsonEncode(key)}:${_canonicalJson(value[key])}';
    }).join(',')}}';
  }
  if (value is List) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  return jsonEncode(value);
}
