import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_models.dart';

/// The five third-party sources the user can enable/disable from the
/// "Third-Party providers" screen: the four catalog browse providers plus
/// Saucepan (a companion-extraction account, not a browse source). Disabling
/// one hides it from the catalog provider picker and hides its settings block
/// on the screen.
enum ThirdPartyProvider { janitor, janny, datacat, chub, saucepan }

extension ThirdPartyProviderX on ThirdPartyProvider {
  /// The matching catalog browse provider, or null for Saucepan (which has no
  /// catalog feed — it only backs local companion extraction).
  CatalogProvider? get catalogProvider => switch (this) {
    ThirdPartyProvider.janitor => CatalogProvider.janitor,
    ThirdPartyProvider.janny => CatalogProvider.janny,
    ThirdPartyProvider.datacat => CatalogProvider.datacat,
    ThirdPartyProvider.chub => CatalogProvider.chub,
    ThirdPartyProvider.saucepan => null,
  };
}

/// Holds the set of DISABLED third-party providers (a provider absent from the
/// set is enabled). Persisted so the choice survives launches; defaults to all
/// enabled (empty set).
class ThirdPartyProvidersNotifier extends Notifier<Set<ThirdPartyProvider>> {
  static const _key = 'gz_disabled_third_party_providers';

  @override
  Set<ThirdPartyProvider> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null) return;
    final disabled = <ThirdPartyProvider>{};
    for (final name in raw) {
      final match = ThirdPartyProvider.values.firstWhereOrNull(
        (p) => p.name == name,
      );
      if (match != null) disabled.add(match);
    }
    if (disabled.isNotEmpty) state = disabled;
  }

  bool isEnabled(ThirdPartyProvider p) => !state.contains(p);

  Future<void> setEnabled(ThirdPartyProvider p, bool enabled) async {
    final next = {...state};
    if (enabled) {
      if (!next.remove(p)) return; // already enabled
    } else {
      if (!next.add(p)) return; // already disabled
    }
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, next.map((p) => p.name).toList());
  }
}

final thirdPartyProvidersProvider =
    NotifierProvider<ThirdPartyProvidersNotifier, Set<ThirdPartyProvider>>(
      ThirdPartyProvidersNotifier.new,
    );

/// The catalog browse providers currently enabled, in enum order. Never empty:
/// if the user somehow disabled all four, janitor is force-kept as a fallback
/// so the catalog always has a feed to show.
final enabledCatalogProvidersProvider = Provider<List<CatalogProvider>>((ref) {
  final disabled = ref.watch(thirdPartyProvidersProvider);
  final enabled = <CatalogProvider>[];
  for (final tp in ThirdPartyProvider.values) {
    final cp = tp.catalogProvider;
    if (cp != null && !disabled.contains(tp)) enabled.add(cp);
  }
  return enabled.isEmpty ? const [CatalogProvider.janitor] : enabled;
});
