import 'dart:convert';

import '../../../data_layer/models/nip_01_event_model.dart';
import '../nip_01_event.dart';
import 'marketplace_constants.dart';
import 'order.dart';

enum MarketplaceOrderTransitionType {
  counterOffer,
  commit,
  cancel,
  confirm,
}

class MarketplaceOrderTransitionContent {
  final MarketplaceOrderTransitionType transitionType;
  final MarketplaceOrderStage fromStage;
  final MarketplaceOrderStage toStage;
  final String? commitTermsHash;
  final String? reason;
  final Map<String, dynamic>? updatedFields;

  const MarketplaceOrderTransitionContent({
    required this.transitionType,
    required this.fromStage,
    required this.toStage,
    this.commitTermsHash,
    this.reason,
    this.updatedFields,
  });

  factory MarketplaceOrderTransitionContent.fromJson(
    Map<String, dynamic> json,
  ) {
    return MarketplaceOrderTransitionContent(
      transitionType: MarketplaceOrderTransitionType.values.firstWhere(
        (type) => type.name == json['transitionType'],
      ),
      fromStage: MarketplaceOrderStage.values.firstWhere(
        (stage) => stage.name == json['fromStage'],
      ),
      toStage: MarketplaceOrderStage.values.firstWhere(
        (stage) => stage.name == json['toStage'],
      ),
      commitTermsHash: json['commitTermsHash'] as String?,
      reason: json['reason'] as String?,
      updatedFields: json['updatedFields'] == null
          ? null
          : Map<String, dynamic>.from(json['updatedFields'] as Map),
    );
  }

  Map<String, dynamic> toJson() => {
        'transitionType': transitionType.name,
        'fromStage': fromStage.name,
        'toStage': toStage.name,
        if (commitTermsHash != null) 'commitTermsHash': commitTermsHash,
        if (reason != null) 'reason': reason,
        if (updatedFields != null) 'updatedFields': updatedFields,
      };
}

class MarketplaceOrderTransition extends Nip01Event {
  MarketplaceOrderTransition({
    super.id,
    required super.pubKey,
    required super.tags,
    required MarketplaceOrderTransitionContent transitionContent,
    super.sig,
    super.validSig,
    super.sources,
    int? createdAt,
  }) : super(
          kind: MarketplaceKinds.orderTransition,
          content: jsonEncode(transitionContent.toJson()),
          createdAt: createdAt ?? Nip01Event.secondsSinceEpoch(),
        );

  MarketplaceOrderTransition.fromEvent(Nip01Event event)
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
    if (event.kind != MarketplaceKinds.orderTransition) {
      throw ArgumentError(
        'Event kind ${event.kind} is not a marketplace order transition',
      );
    }
  }

  factory MarketplaceOrderTransition.create({
    required String pubKey,
    required MarketplaceOrder order,
    required MarketplaceOrderTransitionContent content,
    String? prevTransitionId,
    int? createdAt,
    List<List<String>> extraTags = const [],
  }) {
    final tradeId = order.tradeId;
    final listingAnchor = order.listingAnchor;
    return MarketplaceOrderTransition(
      pubKey: pubKey,
      createdAt: createdAt,
      tags: [
        if (tradeId != null && tradeId.isNotEmpty) ['d', tradeId],
        if (tradeId != null && tradeId.isNotEmpty) ['t', tradeId],
        ['e', order.id],
        if (prevTransitionId != null && prevTransitionId.isNotEmpty)
          ['prev', prevTransitionId],
        if (listingAnchor != null && listingAnchor.isNotEmpty)
          [MarketplaceTags.listingRef, listingAnchor],
        ...extraTags,
      ],
      transitionContent: content,
    );
  }

  MarketplaceOrderTransitionContent get parsedContent {
    return MarketplaceOrderTransitionContent.fromJson(
      Map<String, dynamic>.from(jsonDecode(content) as Map),
    );
  }

  MarketplaceOrderTransitionType get transitionType =>
      parsedContent.transitionType;
  MarketplaceOrderStage get fromStage => parsedContent.fromStage;
  MarketplaceOrderStage get toStage => parsedContent.toStage;
  String? get commitTermsHash => parsedContent.commitTermsHash;
  String? get reason => parsedContent.reason;
  Map<String, dynamic>? get updatedFields => parsedContent.updatedFields;

  String? get tradeId => getFirstTag('d') ?? getFirstTag('t');
  String? get orderEventId => getFirstTag('e');
  String? get prevTransitionId => getFirstTag('prev');
  String? get listingAnchor => getFirstTag(MarketplaceTags.listingRef);

  Nip01EventModel get model => Nip01EventModel.fromEntity(this);
}

class MarketplaceTransitionValidationResult {
  final bool isValid;
  final String? reason;
  final int? failedIndex;

  const MarketplaceTransitionValidationResult.valid()
      : isValid = true,
        reason = null,
        failedIndex = null;

  const MarketplaceTransitionValidationResult.invalid({
    required this.reason,
    required this.failedIndex,
  }) : isValid = false;
}

class MarketplaceTransitionChainResolution {
  final List<MarketplaceOrderTransition> transitions;
  final MarketplaceTransitionValidationResult validation;

  const MarketplaceTransitionChainResolution({
    required this.transitions,
    required this.validation,
  });
}

const _allowedTransitions = <(MarketplaceOrderStage, MarketplaceOrderStage)>{
  (MarketplaceOrderStage.negotiate, MarketplaceOrderStage.negotiate),
  (MarketplaceOrderStage.negotiate, MarketplaceOrderStage.commit),
  (MarketplaceOrderStage.negotiate, MarketplaceOrderStage.cancel),
  (MarketplaceOrderStage.commit, MarketplaceOrderStage.cancel),
  (MarketplaceOrderStage.commit, MarketplaceOrderStage.commit),
};

const _typeToStages = <MarketplaceOrderTransitionType,
    Set<(MarketplaceOrderStage, MarketplaceOrderStage)>>{
  MarketplaceOrderTransitionType.counterOffer: {
    (MarketplaceOrderStage.negotiate, MarketplaceOrderStage.negotiate),
  },
  MarketplaceOrderTransitionType.commit: {
    (MarketplaceOrderStage.negotiate, MarketplaceOrderStage.commit),
  },
  MarketplaceOrderTransitionType.cancel: {
    (MarketplaceOrderStage.negotiate, MarketplaceOrderStage.cancel),
    (MarketplaceOrderStage.commit, MarketplaceOrderStage.cancel),
  },
  MarketplaceOrderTransitionType.confirm: {
    (MarketplaceOrderStage.commit, MarketplaceOrderStage.commit),
  },
};

MarketplaceTransitionChainResolution resolveMarketplaceTransitionChain(
  List<MarketplaceOrderTransition> transitions,
) {
  if (transitions.isEmpty) {
    return const MarketplaceTransitionChainResolution(
      transitions: [],
      validation: MarketplaceTransitionValidationResult.valid(),
    );
  }

  final originalIndex = <MarketplaceOrderTransition, int>{};
  final byId = <String, MarketplaceOrderTransition>{};
  final genesis = <MarketplaceOrderTransition>[];
  final childrenByPrev = <String, List<MarketplaceOrderTransition>>{};

  for (var i = 0; i < transitions.length; i++) {
    final transition = transitions[i];
    originalIndex[transition] = i;
    if (transition.id.isEmpty) {
      return MarketplaceTransitionChainResolution(
        transitions: transitions,
        validation: MarketplaceTransitionValidationResult.invalid(
          reason: 'Transition missing event id (index $i)',
          failedIndex: i,
        ),
      );
    }
    if (byId.containsKey(transition.id)) {
      return MarketplaceTransitionChainResolution(
        transitions: transitions,
        validation: MarketplaceTransitionValidationResult.invalid(
          reason: 'Duplicate transition id ${transition.id} (index $i)',
          failedIndex: i,
        ),
      );
    }
    byId[transition.id] = transition;
  }

  for (var i = 0; i < transitions.length; i++) {
    final transition = transitions[i];
    final prev = transition.prevTransitionId;
    if (prev == null || prev.isEmpty) {
      genesis.add(transition);
      continue;
    }
    final parent = byId[prev];
    if (parent == null) {
      return MarketplaceTransitionChainResolution(
        transitions: transitions,
        validation: MarketplaceTransitionValidationResult.invalid(
          reason: 'Missing previous transition $prev (index $i)',
          failedIndex: i,
        ),
      );
    }
    childrenByPrev.putIfAbsent(prev, () => []).add(transition);
  }

  if (genesis.isEmpty) {
    return const MarketplaceTransitionChainResolution(
      transitions: [],
      validation: MarketplaceTransitionValidationResult.invalid(
        reason: 'No genesis transition: first transition must omit prev',
        failedIndex: 0,
      ),
    );
  }

  if (genesis.length > 1) {
    return MarketplaceTransitionChainResolution(
      transitions: transitions,
      validation: MarketplaceTransitionValidationResult.invalid(
        reason:
            'Multiple genesis transitions; later transitions must include prev',
        failedIndex: originalIndex[genesis[1]] ?? 1,
      ),
    );
  }

  for (final entry in childrenByPrev.entries) {
    if (entry.value.length > 1) {
      return MarketplaceTransitionChainResolution(
        transitions: transitions,
        validation: MarketplaceTransitionValidationResult.invalid(
          reason: 'Transition fork: multiple children reference ${entry.key}',
          failedIndex: originalIndex[entry.value[1]] ?? 0,
        ),
      );
    }
  }

  final ordered = <MarketplaceOrderTransition>[];
  final visited = <String>{};
  var current = genesis.first;

  while (true) {
    if (!visited.add(current.id)) {
      return MarketplaceTransitionChainResolution(
        transitions: ordered,
        validation: MarketplaceTransitionValidationResult.invalid(
          reason: 'Transition cycle at ${current.id}',
          failedIndex: originalIndex[current] ?? 0,
        ),
      );
    }
    ordered.add(current);
    final children = childrenByPrev[current.id] ?? const [];
    if (children.isEmpty) break;
    current = children.single;
  }

  if (ordered.length != transitions.length) {
    final disconnected = transitions.firstWhere(
      (transition) => !visited.contains(transition.id),
    );
    return MarketplaceTransitionChainResolution(
      transitions: ordered,
      validation: MarketplaceTransitionValidationResult.invalid(
        reason: 'Disconnected transition chain',
        failedIndex: originalIndex[disconnected] ?? 0,
      ),
    );
  }

  return MarketplaceTransitionChainResolution(
    transitions: ordered,
    validation: validateMarketplaceStateTransitions(ordered),
  );
}

MarketplaceTransitionValidationResult validateMarketplaceStateTransitions(
  List<MarketplaceOrderTransition> transitions,
) {
  MarketplaceOrderStage? currentStage;

  for (var i = 0; i < transitions.length; i++) {
    final transition = transitions[i];
    final from = transition.fromStage;
    final to = transition.toStage;

    if (!_allowedTransitions.contains((from, to))) {
      return MarketplaceTransitionValidationResult.invalid(
        reason: 'Illegal transition ${from.name} -> ${to.name} (index $i)',
        failedIndex: i,
      );
    }

    final allowed = _typeToStages[transition.transitionType];
    if (allowed != null && !allowed.contains((from, to))) {
      return MarketplaceTransitionValidationResult.invalid(
        reason: 'Transition type ${transition.transitionType.name} does not '
            'match stages ${from.name} -> ${to.name} (index $i)',
        failedIndex: i,
      );
    }

    if (currentStage != null && from != currentStage) {
      return MarketplaceTransitionValidationResult.invalid(
        reason: 'Chain break: expected fromStage=${currentStage.name} '
            'but got ${from.name} (index $i)',
        failedIndex: i,
      );
    }

    currentStage = to;
  }

  return const MarketplaceTransitionValidationResult.valid();
}

MarketplaceTransitionValidationResult validateMarketplaceEscrowTransitions(
  List<MarketplaceOrderTransition> transitions,
) {
  final resolution = resolveMarketplaceTransitionChain(transitions);
  if (!resolution.validation.isValid) return resolution.validation;

  for (var i = 0; i < resolution.transitions.length; i++) {
    final transition = resolution.transitions[i];
    if (transition.fromStage == MarketplaceOrderStage.commit &&
        transition.toStage == MarketplaceOrderStage.cancel) {
      return MarketplaceTransitionValidationResult.invalid(
        reason: 'Escrow cannot cancel after commit (index $i)',
        failedIndex: i,
      );
    }
  }

  return const MarketplaceTransitionValidationResult.valid();
}
