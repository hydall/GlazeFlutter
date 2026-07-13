typedef MessageContextCallback =
    void Function(
      int index,
      String messageId,
      bool isUser,
      bool isSystem,
      String content,
    );
typedef SwipeCallback = void Function(String id, String direction);
typedef GreetingCallback = void Function(String id, int direction);
typedef RegenerateCallback = void Function(String id, String mode);
typedef RerunCleanerCallback = void Function(String messageId);
typedef ToggleHiddenCallback = void Function(String id);
typedef InjectClickCallback = void Function(String id);
typedef MemoryClickCallback = void Function(String id);
typedef GuidedSwipeCallback = void Function(String id, String guidanceText);
typedef EditSaveCallback = void Function(String id, String text);
typedef EditCancelCallback = void Function(String id);
typedef EditFocusCallback = void Function(String id, bool focused);
typedef ImgActionCallback = void Function(String instruction, String messageId);
typedef ImgOptionsCallback =
    void Function(String src, String instruction, String messageId);
typedef ImgVoidCallback = void Function();
typedef HeaderScrollCallback = void Function(bool hidden);
typedef ScrollToBottomVisibilityCallback = void Function(bool visible);
typedef SelectionActionCallback = void Function(String action, String text);
typedef ImageClickCallback = void Function(String imageUrl);
typedef SelectionChangeCallback = void Function(List<String> ids);

class MessageActionsCallbacks {
  final MessageContextCallback? onMessageContext;
  final SwipeCallback? onSwipe;
  final SwipeCallback? onAgentSwipe;
  final GreetingCallback? onChangeGreeting;
  final RegenerateCallback? onRegenerate;
  final RerunCleanerCallback? onRerunCleaner;
  final ToggleHiddenCallback? onToggleHidden;
  final InjectClickCallback? onInjectClick;
  final MemoryClickCallback? onMemoryClick;
  final GuidedSwipeCallback? onGuidedSwipe;

  const MessageActionsCallbacks({
    this.onMessageContext,
    this.onSwipe,
    this.onAgentSwipe,
    this.onChangeGreeting,
    this.onRegenerate,
    this.onRerunCleaner,
    this.onToggleHidden,
    this.onInjectClick,
    this.onMemoryClick,
    this.onGuidedSwipe,
  });
}

class EditActionsCallbacks {
  final EditSaveCallback? onEditSave;
  final EditCancelCallback? onEditCancel;
  final EditFocusCallback? onEditFocusChange;

  const EditActionsCallbacks({
    this.onEditSave,
    this.onEditCancel,
    this.onEditFocusChange,
  });
}

class ImageGenCallbacks {
  final ImgActionCallback? onImgRetry;
  final ImgActionCallback? onImgFind;
  final ImgActionCallback? onImgRegen;
  final ImgOptionsCallback? onImgOptions;
  final ImgVoidCallback? onImgCancel;
  final ImageClickCallback? onImgDownload;

  const ImageGenCallbacks({
    this.onImgRetry,
    this.onImgFind,
    this.onImgRegen,
    this.onImgOptions,
    this.onImgCancel,
    this.onImgDownload,
  });
}

class ScrollCallbacks {
  final HeaderScrollCallback? onHeaderScroll;
  final ScrollToBottomVisibilityCallback? onScrollToBottomVisibility;

  const ScrollCallbacks({this.onHeaderScroll, this.onScrollToBottomVisibility});
}

/// Callbacks for the in-WebView input bar (Phase 2). The compose field +
/// buttons live in the WebView; these forward gestures to the chat provider
/// and drawer controls the native ChatInputBar used to drive.
class InputCallbacks {
  final void Function(String text, String? guidance, String? imageDataUrl)?
  onInputSend;
  final ImgVoidCallback? onInputStop;
  final ImgVoidCallback? onInputImpersonate;
  final void Function(String text)? onInputDraftChanged;
  final void Function(bool focused)? onInputFocus;
  final void Function(double height, bool open)? onKeyboardInset;
  final void Function(String text)? onFullScreenEditor;
  final ImgVoidCallback? onMagicDrawer;
  final ImgVoidCallback? onQuickReplies;
  final ImgVoidCallback? onSearchNext;
  final ImgVoidCallback? onSearchPrev;
  final ImgVoidCallback? onCancelSelection;
  final ImgVoidCallback? onHideSelected;
  final ImgVoidCallback? onDeleteSelected;
  final ImgVoidCallback? onScrollToBottomTap;

  const InputCallbacks({
    this.onInputSend,
    this.onInputStop,
    this.onInputImpersonate,
    this.onInputDraftChanged,
    this.onInputFocus,
    this.onKeyboardInset,
    this.onFullScreenEditor,
    this.onMagicDrawer,
    this.onQuickReplies,
    this.onSearchNext,
    this.onSearchPrev,
    this.onCancelSelection,
    this.onHideSelected,
    this.onDeleteSelected,
    this.onScrollToBottomTap,
  });
}

class MiscCallbacks {
  final ImgVoidCallback? onStop;
  final SelectionActionCallback? onSelectionAction;
  final ImageClickCallback? onImageClick;
  final SelectionChangeCallback? onSelectionChange;

  /// In-WebView header buttons (the header now lives inside the chat WebView):
  /// back navigates up, search enters the native search bar.
  final ImgVoidCallback? onHeaderBack;
  final ImgVoidCallback? onHeaderSearch;

  const MiscCallbacks({
    this.onStop,
    this.onSelectionAction,
    this.onImageClick,
    this.onSelectionChange,
    this.onHeaderBack,
    this.onHeaderSearch,
  });
}
