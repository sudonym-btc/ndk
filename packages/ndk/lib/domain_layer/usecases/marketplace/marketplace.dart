import '../accounts/accounts.dart';
import '../broadcast/broadcast.dart';
import '../gift_wrap/gift_wrap.dart';
import '../requests/requests.dart';
import 'escrow_usecase.dart';
import 'hd_usecase.dart';
import 'listing_usecase.dart';
import 'offers_usecase.dart';
import 'order_transition_usecase.dart';
import 'order_usecase.dart';

class Marketplace {
  final MarketplaceListingUsecase listing;
  final MarketplaceOrderUsecase orders;
  final MarketplaceEscrowMethodUsecase escrowMethod;
  final MarketplaceEscrowUsecase escrow;
  final MarketplaceHdUsecase hd;
  final MarketplaceOffersUsecase offers;
  final MarketplaceOrderTransitionsUsecase orderTransitions;

  Marketplace({
    required Requests requests,
    required Broadcast broadcast,
    required Accounts accounts,
    required GiftWrap giftWrap,
    MarketplaceAccountIndexStore? accountIndexStore,
  })  : listing = MarketplaceListingUsecase(
          requests: requests,
          broadcast: broadcast,
          accounts: accounts,
        ),
        orders = MarketplaceOrderUsecase(
          requests: requests,
          broadcast: broadcast,
          accounts: accounts,
          giftWrap: giftWrap,
        ),
        escrowMethod = MarketplaceEscrowMethodUsecase(requests: requests),
        escrow = MarketplaceEscrowUsecase(requests: requests),
        hd = MarketplaceHdUsecase(accounts: accounts, store: accountIndexStore),
        offers = MarketplaceOffersUsecase(
          requests: requests,
          giftWrap: giftWrap,
          accounts: accounts,
        ),
        orderTransitions = MarketplaceOrderTransitionsUsecase(
          requests: requests,
          broadcast: broadcast,
          accounts: accounts,
        );
}
