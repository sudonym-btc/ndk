import '../filter.dart';
import '../nip_01_event.dart';
import 'marketplace_amount.dart';
import 'marketplace_constants.dart';

List<String> marketplaceTagValues(List<List<String>> tags, String name) {
  return [
    for (final tag in tags)
      if (tag.length >= 2 && tag.first == name) tag[1],
  ];
}

class MarketplaceCancellationPolicy {
  final int secondsBeforeStart;
  final String refundFraction;

  const MarketplaceCancellationPolicy({
    required this.secondsBeforeStart,
    required this.refundFraction,
  });

  List<String> toTag() => [
        'cancellationPolicy',
        secondsBeforeStart.toString(),
        refundFraction,
      ];
}

class MarketplaceListingProperties {
  final String? dTag;
  final String title;
  final String description;
  final String? summary;
  final List<String> images;
  final int? publishedAt;
  final String status;
  final List<MarketplacePrice> prices;
  final String? location;
  final int quantity;
  final bool instantBook;
  final bool negotiable;
  final MarketplaceAmount? securityDeposit;
  final MarketplaceAmount? minPaymentAmount;
  final int? maxDisputePeriod;
  final List<MarketplaceCancellationPolicy> cancellationPolicies;
  final List<List<String>> extraTags;

  const MarketplaceListingProperties({
    this.dTag,
    required this.title,
    required this.description,
    this.summary,
    this.images = const [],
    this.publishedAt,
    this.status = 'active',
    this.prices = const [],
    this.location,
    this.quantity = 1,
    this.instantBook = false,
    this.negotiable = false,
    this.securityDeposit,
    this.minPaymentAmount,
    this.maxDisputePeriod,
    this.cancellationPolicies = const [],
    this.extraTags = const [],
  });
}

abstract class BaseListing extends Nip01Event {
  BaseListing({
    super.id,
    required super.pubKey,
    required super.kind,
    required super.tags,
    required super.content,
    super.sig,
    super.validSig,
    super.sources,
    int? createdAt,
  }) : super(createdAt: createdAt ?? Nip01Event.secondsSinceEpoch());

  BaseListing.fromEvent(Nip01Event event)
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
        );

  String? get dTag => getDtag();
  String? get title => getFirstTag('title');
  String? get summary => getFirstTag('summary');
  String? get status => getFirstTag('status');
  String? get location => getFirstTag('location');
  int get quantity => int.tryParse(getFirstTag('quantity') ?? '') ?? 1;
  bool get instantBook => getFirstTag('instantBook') == 'true';
  bool get negotiable => getFirstTag('negotiable') == 'true';
  List<String> get profiles =>
      marketplaceTagValues(tags, MarketplaceTags.profile);
  List<String> get images => marketplaceTagValues(tags, 'image');

  String get anchor {
    final d = dTag;
    if (d == null || d.isEmpty) {
      throw StateError('Marketplace listings require a d tag');
    }
    return '$kind:$pubKey:$d';
  }

  List<MarketplacePrice> get prices {
    return tags
        .where((tag) => tag.isNotEmpty && tag.first == 'price')
        .map(MarketplacePrice.fromTag)
        .toList(growable: false);
  }

  MarketplaceAmount cost({DateTime? start, DateTime? end, int quantity = 1}) {
    final availablePrices = prices;
    if (availablePrices.isEmpty) {
      throw StateError('Listing has no price tags');
    }

    final costs = <MarketplaceAmount>[];
    for (final price in availablePrices) {
      try {
        costs.add(price.cost(start: start, end: end, quantity: quantity));
      } on ArgumentError {
        // Recurring prices without dates cannot be quoted.
      }
    }
    if (costs.isEmpty) {
      costs.add(availablePrices.first.amount * quantity);
    }
    costs.sort();
    return costs.first;
  }

  BaseListing copyWithPubKey(String pubKey);
}

List<List<String>> buildBaseListingTags(MarketplaceListingProperties props) {
  final publishedAt = props.publishedAt ?? Nip01Event.secondsSinceEpoch();
  var tags = <List<String>>[
    ['d', props.dTag ?? 'listing-$publishedAt'],
    ['title', props.title],
    if (props.summary != null) ['summary', props.summary!],
    ['published_at', publishedAt.toString()],
    ['status', props.status],
    for (final image in props.images) ['image', image],
    for (final price in props.prices) price.toTag(),
    if (props.location != null) ['location', props.location!],
    ['quantity', props.quantity.toString()],
    ['instantBook', props.instantBook.toString()],
    ['I', props.instantBook.toString()],
    ['negotiable', props.negotiable.toString()],
    ['N', props.negotiable.toString()],
    if (props.securityDeposit != null)
      [
        'securityDeposit',
        props.securityDeposit!.toDecimalString(),
        props.securityDeposit!.denomination,
        props.securityDeposit!.decimals.toString(),
      ],
    if (props.minPaymentAmount != null)
      [
        'minPaymentAmount',
        props.minPaymentAmount!.toDecimalString(),
        props.minPaymentAmount!.denomination,
        props.minPaymentAmount!.decimals.toString(),
      ],
    if (props.maxDisputePeriod != null)
      ['maxDisputePeriod', props.maxDisputePeriod.toString()],
    for (final policy in props.cancellationPolicies) policy.toTag(),
    ...props.extraTags,
  ];
  return tags;
}

abstract class MarketplaceListingTags<T extends BaseListing> {
  const MarketplaceListingTags();
  Filter toFilter({int? limit});
  T fromEvent(Nip01Event event);
}
