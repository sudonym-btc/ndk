/// Event kinds used by the Hostr marketplace NIPs.
class MarketplaceKinds {
  static const int listing = 30402;
  static const int draftListing = 30403;
  static const int order = 32122;
  static const int orderTransition = 1326;
  static const int structuredMessage = 1327;
  static const int commitAuthorization = 1328;
  static const int tempKeyAuthorization = 1329;
  static const int review = 32124;
  static const int escrowMethod = 17388;
  static const int escrowService = 30303;
  static const int escrowServiceSelected = 30302;
}

class MarketplaceTags {
  static const String listingRef = 'a';
  static const String publishedAt = 'published_at';
  static const String profile = 't';
  static const String accommodation = 'accommodation';
  static const String participantProof = 'participant_proof';
  static const String shippingOption = 'shipping_option';
  static const String conversation = 'conversation';
}
