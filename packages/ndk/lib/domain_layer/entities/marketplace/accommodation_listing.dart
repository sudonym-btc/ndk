import '../filter.dart';
import '../nip_01_event.dart';
import 'listing.dart';
import 'marketplace_constants.dart';

class AccommodationListingProperties extends MarketplaceListingProperties {
  final String? accommodationType;
  final int? minStay;
  final String? checkIn;
  final String? checkOut;
  final Map<String, Object?> specs;
  final List<String> h3Cells;

  const AccommodationListingProperties({
    super.dTag,
    required super.title,
    required super.description,
    super.summary,
    super.images,
    super.publishedAt,
    super.status,
    super.prices,
    super.location,
    super.quantity,
    super.instantBook,
    super.negotiable,
    super.securityDeposit,
    super.minPaymentAmount,
    super.maxDisputePeriod,
    super.cancellationPolicies,
    super.extraTags,
    this.accommodationType,
    this.minStay,
    this.checkIn,
    this.checkOut,
    this.specs = const {},
    this.h3Cells = const [],
  });
}

class AccommodationListing extends BaseListing {
  AccommodationListing(
    AccommodationListingProperties properties, {
    super.pubKey = '',
    super.kind = MarketplaceKinds.listing,
    super.createdAt,
    super.id,
    super.sig,
  }) : super(
          tags: _buildAccommodationTags(properties),
          content: properties.description,
        );

  AccommodationListing._raw({
    required super.pubKey,
    required super.kind,
    required super.tags,
    required super.content,
    super.createdAt,
  });

  AccommodationListing.fromEvent(super.event) : super.fromEvent();

  String? get accommodationType => getFirstTag('type');
  int? get minStay => int.tryParse(getFirstTag('minStay') ?? '');
  String? get checkIn => getFirstTag('checkIn');
  String? get checkOut => getFirstTag('checkOut');
  List<String> get h3Cells => marketplaceTagValues(tags, 'g');
  List<String> get booleanSpecs => marketplaceTagValues(tags, 's');

  String? spec(String name) {
    for (final tag in tags) {
      if (tag.length >= 2 && tag.first == 'spec' && tag[1] == name) {
        return tag.length >= 3 ? tag[2] : 'true';
      }
    }
    return null;
  }

  @override
  AccommodationListing copyWithPubKey(String pubKey) {
    return AccommodationListing._raw(
      pubKey: pubKey,
      kind: kind,
      tags: tags,
      content: content,
      createdAt: createdAt,
    );
  }

  static List<List<String>> _buildAccommodationTags(
    AccommodationListingProperties props,
  ) {
    final tags = buildBaseListingTags(props);
    tags.add(['t', MarketplaceTags.accommodation]);
    if (props.accommodationType != null) {
      tags.add(['type', props.accommodationType!]);
      tags.add(['T', props.accommodationType!]);
    }
    if (props.minStay != null) {
      tags.add(['minStay', props.minStay.toString()]);
    }
    if (props.checkIn != null) {
      tags.add(['checkIn', props.checkIn!]);
    }
    if (props.checkOut != null) {
      tags.add(['checkOut', props.checkOut!]);
    }
    for (final entry in props.specs.entries) {
      final value = entry.value;
      if (value == null || value == false) continue;
      if (value == true) {
        tags.add(['spec', entry.key]);
        tags.add(['s', entry.key]);
      } else {
        tags.add(['spec', entry.key, value.toString()]);
        switch (entry.key) {
          case 'max_guests':
            tags.add(['c', value.toString()]);
            break;
          case 'beds':
            tags.add(['b', value.toString()]);
            break;
          case 'bedrooms':
            tags.add(['B', value.toString()]);
            break;
          case 'bathrooms':
            tags.add(['R', value.toString()]);
            break;
        }
      }
    }
    for (final cell in props.h3Cells) {
      tags.add(['g', cell]);
    }
    return tags;
  }
}

class AccommodationListingTags
    extends MarketplaceListingTags<AccommodationListing> {
  final List<String>? authors;
  final List<String>? dTags;
  final List<String>? accommodationTypes;
  final List<String>? h3Cells;
  final List<String>? booleanSpecs;
  final int? guests;
  final bool? instantBook;
  final bool? negotiable;
  final String? search;
  final int? since;
  final int? until;
  final int defaultLimit;

  const AccommodationListingTags({
    this.authors,
    this.dTags,
    this.accommodationTypes,
    this.h3Cells,
    this.booleanSpecs,
    this.guests,
    this.instantBook,
    this.negotiable,
    this.search,
    this.since,
    this.until,
    this.defaultLimit = 100,
  });

  @override
  Filter toFilter({int? limit}) {
    final tags = <String, List<String>>{
      '#t': [MarketplaceTags.accommodation],
      if (dTags != null && dTags!.isNotEmpty) '#d': dTags!,
      if (accommodationTypes != null && accommodationTypes!.isNotEmpty)
        '#T': accommodationTypes!,
      if (h3Cells != null && h3Cells!.isNotEmpty) '#g': h3Cells!,
      if (booleanSpecs != null && booleanSpecs!.isNotEmpty) '#s': booleanSpecs!,
      if (guests != null) '#c': [guests.toString()],
      if (instantBook != null) '#I': [instantBook.toString()],
      if (negotiable != null) '#N': [negotiable.toString()],
    };

    return Filter(
      authors: authors,
      kinds: const [MarketplaceKinds.listing],
      tags: tags,
      search: search,
      since: since,
      until: until,
      limit: limit ?? defaultLimit,
    );
  }

  @override
  AccommodationListing fromEvent(Nip01Event event) {
    return AccommodationListing.fromEvent(event);
  }
}
