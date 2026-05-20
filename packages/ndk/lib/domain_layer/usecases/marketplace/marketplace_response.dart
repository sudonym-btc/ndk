import 'dart:async';

class MarketplaceResponse<T> {
  final String requestId;
  final Stream<T> stream;

  const MarketplaceResponse(this.requestId, this.stream);

  Future<List<T>> get future => stream.toList();
}
