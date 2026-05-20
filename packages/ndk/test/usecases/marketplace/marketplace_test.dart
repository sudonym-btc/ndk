import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:test/test.dart';

import '../../mocks/mock_event_verifier.dart';

void main() {
  const sellerPubkey =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const buyerPubkey =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  AccommodationListing buildListing() {
    return AccommodationListing(
      AccommodationListingProperties(
        dTag: 'villa-1',
        title: 'Ocean View Villa',
        summary: 'Two bedroom beachfront villa',
        description: 'A beautiful beachfront villa with a private pool.',
        accommodationType: 'villa',
        location: 'Bali, Indonesia',
        prices: [
          MarketplacePrice(
            amount: MarketplaceAmount.fromDecimal(
              '10',
              denomination: 'USD',
              decimals: MarketplaceAmount.decimalsFor('USD'),
            ),
            frequency: 'day',
          ),
        ],
        instantBook: true,
        negotiable: false,
        specs: const {
          'wireless_internet': true,
          'pool': true,
          'max_guests': 4,
          'beds': 2,
        },
        h3Cells: const ['8c2ab34567fffff', '8b2ab34567fffff'],
      ),
      pubKey: sellerPubkey,
      createdAt: 1712678400,
    );
  }

  group('marketplace listings', () {
    test(
      'builds an accommodation listing with canonical and promoted tags',
      () {
        final listing = buildListing();

        expect(listing.kind, MarketplaceKinds.listing);
        expect(listing.anchor, '30402:$sellerPubkey:villa-1');
        expect(listing.title, 'Ocean View Villa');
        expect(listing.accommodationType, 'villa');
        expect(listing.instantBook, isTrue);
        expect(
          listing.booleanSpecs,
          containsAll(['wireless_internet', 'pool']),
        );
        expect(listing.spec('max_guests'), '4');
        expect(listing.h3Cells, contains('8c2ab34567fffff'));
      },
    );

    test('accommodation tag object creates a typed relay filter', () {
      const tags = AccommodationListingTags(
        authors: [sellerPubkey],
        accommodationTypes: ['villa'],
        booleanSpecs: ['pool'],
        guests: 4,
        instantBook: true,
      );

      final filter = tags.toFilter();
      expect(filter.kinds, [MarketplaceKinds.listing]);
      expect(filter.authors, [sellerPubkey]);
      expect(filter.tags!['#t'], ['accommodation']);
      expect(filter.tags!['#T'], ['villa']);
      expect(filter.tags!['#s'], ['pool']);
      expect(filter.tags!['#c'], ['4']);
      expect(filter.tags!['#I'], ['true']);

      final parsed = tags.fromEvent(buildListing());
      expect(parsed, isA<AccommodationListing>());
      expect(parsed.anchor, '30402:$sellerPubkey:villa-1');
    });
  });

  group('marketplace orders', () {
    test('quotes listing cost plus shipping and extra charges', () {
      final ndk = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: const [],
        ),
      );
      final listing = buildListing();
      final start = DateTime.utc(2026, 5, 1);
      final end = DateTime.utc(2026, 5, 3);

      final properties = OrderProperties(
        dTag: 'trade-1',
        start: start,
        end: end,
        shippingOptions: [
          OrderShippingOptionSelection(
            optionAnchor: '30406:$sellerPubkey:standard-us',
            country: 'US',
            amount: MarketplaceAmount.fromDecimal(
              '5',
              denomination: 'USD',
              decimals: MarketplaceAmount.decimalsFor('USD'),
            ),
          ),
        ],
        charges: [
          MarketplaceCharge(
            type: 'cleaning',
            amount: MarketplaceAmount.fromDecimal(
              '2',
              denomination: 'USD',
              decimals: MarketplaceAmount.decimalsFor('USD'),
            ),
          ),
        ],
      );

      final quote = ndk.marketplace.orders.quote(listing, properties);
      expect(quote.toDecimalString(trimTrailingZeros: true), '27');

      final order = ndk.marketplace.orders.build(
        listing,
        properties,
        pubKey: buyerPubkey,
      );
      expect(order.kind, MarketplaceKinds.order);
      expect(order.tradeId, 'trade-1');
      expect(order.listingAnchor, listing.anchor);
      expect(order.stage, MarketplaceOrderStage.negotiate);
      expect(order.amount!.toDecimalString(trimTrailingZeros: true), '27');
      expect(order.parsedContent.shippingOptions.single.country, 'US');
    });

    test('proof defaults the order stage to commit', () {
      final ndk = Ndk(
        NdkConfig(
          eventVerifier: MockEventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: const [],
        ),
      );

      final order = ndk.marketplace.orders.build(
        buildListing(),
        const OrderProperties(dTag: 'trade-2', proof: 'tx-proof'),
        pubKey: buyerPubkey,
      );

      expect(order.stage, MarketplaceOrderStage.commit);
      expect(order.parsedContent.proof, 'tx-proof');
    });
  });

  group('marketplace HD', () {
    test(
      'allocates account indices with an optional used-index callback',
      () async {
        final key = Bip340.generatePrivateKey();
        final ndk = Ndk(
          NdkConfig(
            eventVerifier: MockEventVerifier(),
            cache: MemCacheManager(),
            bootstrapRelays: const [],
          ),
        );
        ndk.accounts.loginPrivateKey(
          pubkey: key.publicKey,
          privkey: key.privateKey!,
        );

        expect(await ndk.marketplace.hd.getNextAccountIndex(), 1);
        final next = await ndk.marketplace.hd.getNextAccountIndex(
          isIndexUsed: (index) async => index == 2,
        );
        expect(next, 3);
      },
    );
  });

  group('marketplace escrow', () {
    test('parses escrow methods and services', () {
      final method = MarketplaceEscrowMethod(
        pubKey: sellerPubkey,
        tags: const [
          ['p', buyerPubkey],
          ['c', 'bytecode-hash'],
          ['o', 'USD', '30:0x0000000000000000000000000000000000000000'],
        ],
      );

      expect(method.escrowPubkeys, [buyerPubkey]);
      expect(method.contractBytecodeHashes, ['bytecode-hash']);
      expect(method.paymentForms.single.denomination, 'USD');
    });
  });
}
