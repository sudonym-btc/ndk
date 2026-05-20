import 'dart:math' as math;

/// Decimal-denominated amount stored as integer minor units.
class MarketplaceAmount implements Comparable<MarketplaceAmount> {
  static const denominationDecimals = <String, int>{
    'BTC': 8,
    'USD': 6,
    'ETH': 18,
  };

  final BigInt minorUnits;
  final String denomination;
  final int decimals;

  const MarketplaceAmount({
    required this.minorUnits,
    required this.denomination,
    required this.decimals,
  });

  factory MarketplaceAmount.fromDecimal(
    String value, {
    required String denomination,
    int? decimals,
  }) {
    final trimmed = value.trim();
    final negative = trimmed.startsWith('-');
    final unsigned = negative ? trimmed.substring(1) : trimmed;
    final parts = unsigned.split('.');
    if (parts.length > 2) {
      throw FormatException('Invalid decimal amount: $value');
    }

    final scale = decimals ?? decimalsFor(denomination);
    final fractional = parts.length == 2 ? parts[1] : '';
    if (fractional.length > scale) {
      throw FormatException(
        'Amount $value has more fractional digits than decimals=$scale',
      );
    }

    final whole = parts[0].isEmpty ? '0' : parts[0];
    final paddedFractional = fractional.padRight(scale, '0');
    final raw = '$whole$paddedFractional'.replaceFirst(RegExp(r'^0+'), '');
    final parsed = BigInt.parse(raw.isEmpty ? '0' : raw);
    return MarketplaceAmount(
      minorUnits: negative ? -parsed : parsed,
      denomination: denomination,
      decimals: scale,
    );
  }

  factory MarketplaceAmount.fromJson(Map<String, dynamic> json) {
    return MarketplaceAmount.fromDecimal(
      json['value'] as String,
      denomination: json['denomination'] as String,
      decimals: json['decimals'] as int,
    );
  }

  MarketplaceAmount operator +(MarketplaceAmount other) {
    _assertSameUnit(other);
    return MarketplaceAmount(
      minorUnits: minorUnits + other.minorUnits,
      denomination: denomination,
      decimals: decimals,
    );
  }

  MarketplaceAmount operator *(int multiplier) {
    return MarketplaceAmount(
      minorUnits: minorUnits * BigInt.from(multiplier),
      denomination: denomination,
      decimals: decimals,
    );
  }

  bool sameUnit(MarketplaceAmount other) {
    return denomination == other.denomination && decimals == other.decimals;
  }

  void _assertSameUnit(MarketplaceAmount other) {
    if (!sameUnit(other)) {
      throw ArgumentError(
        'Cannot combine $denomination/$decimals with '
        '${other.denomination}/${other.decimals}',
      );
    }
  }

  static int decimalsFor(String denomination) {
    return denominationDecimals[denomination] ?? 8;
  }

  String toDecimalString({bool trimTrailingZeros = false}) {
    final negative = minorUnits.isNegative;
    final absolute = minorUnits.abs().toString();
    if (decimals == 0) return negative ? '-$absolute' : absolute;

    final padded = absolute.padLeft(decimals + 1, '0');
    final whole = padded.substring(0, padded.length - decimals);
    var fractional = padded.substring(padded.length - decimals);
    if (trimTrailingZeros) {
      fractional = fractional.replaceFirst(RegExp(r'0+$'), '');
    }
    final rendered = fractional.isEmpty ? whole : '$whole.$fractional';
    return negative ? '-$rendered' : rendered;
  }

  Map<String, dynamic> toJson() => {
    'value': toDecimalString(),
    'denomination': denomination,
    'decimals': decimals,
  };

  @override
  int compareTo(MarketplaceAmount other) {
    _assertSameUnit(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  String toString() => '${toDecimalString()} $denomination';

  @override
  bool operator ==(Object other) {
    return other is MarketplaceAmount &&
        minorUnits == other.minorUnits &&
        denomination == other.denomination &&
        decimals == other.decimals;
  }

  @override
  int get hashCode => Object.hash(minorUnits, denomination, decimals);
}

class MarketplacePrice {
  final MarketplaceAmount amount;
  final String? frequency;

  const MarketplacePrice({required this.amount, this.frequency});

  factory MarketplacePrice.fromTag(List<String> tag) {
    if (tag.length < 3 || tag.first != 'price') {
      throw FormatException('Invalid price tag: $tag');
    }
    final value = tag[1];
    final denomination = tag[2];
    final frequency = tag.length >= 4 ? tag[3] : null;
    final decimals = tag.length >= 5 ? int.tryParse(tag[4]) : null;
    return MarketplacePrice(
      amount: MarketplaceAmount.fromDecimal(
        value,
        denomination: denomination,
        decimals: decimals,
      ),
      frequency: frequency,
    );
  }

  List<String> toTag() => [
    'price',
    amount.toDecimalString(),
    amount.denomination,
    if (frequency != null) frequency!,
  ];

  MarketplaceAmount cost({DateTime? start, DateTime? end, int quantity = 1}) {
    if (frequency == null) return amount * quantity;
    if (start == null || end == null) {
      throw ArgumentError('start and end are required for recurring prices');
    }

    final units = _unitsForFrequency(start, end, frequency!);
    return amount * (units * quantity);
  }

  static int _unitsForFrequency(
    DateTime start,
    DateTime end,
    String frequency,
  ) {
    final seconds = end.difference(start).inSeconds.abs();
    final periodSeconds = switch (frequency) {
      'hour' => 3600,
      'day' => 86400,
      'week' => 604800,
      'month' => 2592000,
      'year' => 31536000,
      _ => 86400,
    };
    return math.max(1, (seconds / periodSeconds).ceil());
  }
}

class MarketplaceCharge {
  final String type;
  final MarketplaceAmount amount;
  final String? description;
  final String? reference;

  const MarketplaceCharge({
    required this.type,
    required this.amount,
    this.description,
    this.reference,
  });

  factory MarketplaceCharge.fromJson(Map<String, dynamic> json) {
    return MarketplaceCharge(
      type: json['type'] as String,
      amount: MarketplaceAmount.fromJson(
        Map<String, dynamic>.from(json['amount'] as Map),
      ),
      description: json['description'] as String?,
      reference: json['reference'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'amount': amount.toJson(),
    if (description != null) 'description': description,
    if (reference != null) 'reference': reference,
  };
}
