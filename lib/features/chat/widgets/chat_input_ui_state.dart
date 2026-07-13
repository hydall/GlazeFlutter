import '../bridge/chat_bridge_controller.dart';

/// Immutable snapshot of the reactive state the in-WebView input bar needs
/// (Phase 2). Bundled into a single value object so it threads through the
/// WebView widget / sync-dispatcher / initializer as one field instead of a
/// dozen, and so the dispatcher can diff it with a plain `!=`.
///
/// All user-facing strings (placeholders, search / selection labels) are
/// pre-localized by the Flutter side — the WebView has no i18n.
///
/// NOTE: the draft text is deliberately NOT part of this reactive state. The
/// WebView is the sole editor of the compose field; Flutter only pushes the
/// draft on discrete events (initial load, session switch, fullscreen-editor
/// save) via [ChatWebViewWidgetState.applyDraft]. Echoing the debounced draft
/// back on every keystroke would overwrite the field mid-typing.
class ChatInputUiState {
  /// Bottom safe-area inset in logical px (pushed so the idle input bar clears
  /// the home indicator / nav bar). `env(safe-area-inset-bottom)` is unreliable
  /// inside the platform WebView, mirroring the header's `safeTop`.
  final double safeBottom;
  final String placeholder;
  final String guidancePlaceholder;
  final bool isGenerating;
  final bool isEditing;
  final bool isDrawerOpen;
  final bool isQuickRepliesOpen;
  final bool isSelectionMode;
  final bool showSearch;
  final String searchLabel;
  final String selectionLabel;
  final int selectedCount;
  final bool allSelectedHidden;
  final bool enterToSend;
  final bool virtualKeyboardSend;

  const ChatInputUiState({
    this.safeBottom = 0,
    this.placeholder = '',
    this.guidancePlaceholder = '',
    this.isGenerating = false,
    this.isEditing = false,
    this.isDrawerOpen = false,
    this.isQuickRepliesOpen = false,
    this.isSelectionMode = false,
    this.showSearch = false,
    this.searchLabel = '',
    this.selectionLabel = '',
    this.selectedCount = 0,
    this.allSelectedHidden = false,
    this.enterToSend = true,
    this.virtualKeyboardSend = false,
  });

  @override
  bool operator ==(Object other) {
    return other is ChatInputUiState &&
        other.safeBottom == safeBottom &&
        other.placeholder == placeholder &&
        other.guidancePlaceholder == guidancePlaceholder &&
        other.isGenerating == isGenerating &&
        other.isEditing == isEditing &&
        other.isDrawerOpen == isDrawerOpen &&
        other.isQuickRepliesOpen == isQuickRepliesOpen &&
        other.isSelectionMode == isSelectionMode &&
        other.showSearch == showSearch &&
        other.searchLabel == searchLabel &&
        other.selectionLabel == selectionLabel &&
        other.selectedCount == selectedCount &&
        other.allSelectedHidden == allSelectedHidden &&
        other.enterToSend == enterToSend &&
        other.virtualKeyboardSend == virtualKeyboardSend;
  }

  @override
  int get hashCode => Object.hash(
    safeBottom,
    placeholder,
    guidancePlaceholder,
    isGenerating,
    isEditing,
    isDrawerOpen,
    isQuickRepliesOpen,
    isSelectionMode,
    showSearch,
    searchLabel,
    selectionLabel,
    selectedCount,
    allSelectedHidden,
    enterToSend,
    virtualKeyboardSend,
  );
}

/// Pushes [s] to the WebView input bar. Shared by the initial-load
/// initializer and the per-frame sync dispatcher so the mapping lives once.
Future<void> applyInputStateToBridge(
  ChatBridgeController bridge,
  ChatInputUiState s,
) {
  return bridge.setInputState(
    safeBottom: s.safeBottom,
    placeholder: s.placeholder,
    guidancePlaceholder: s.guidancePlaceholder,
    isGenerating: s.isGenerating,
    isEditing: s.isEditing,
    isDrawerOpen: s.isDrawerOpen,
    isQuickRepliesOpen: s.isQuickRepliesOpen,
    isSelectionMode: s.isSelectionMode,
    showSearch: s.showSearch,
    searchLabel: s.searchLabel,
    selectionLabel: s.selectionLabel,
    selectedCount: s.selectedCount,
    allSelectedHidden: s.allSelectedHidden,
    enterToSend: s.enterToSend,
    virtualKeyboardSend: s.virtualKeyboardSend,
  );
}
