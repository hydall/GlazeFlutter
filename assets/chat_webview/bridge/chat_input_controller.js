/* Chat input bar controller (ported from the Flutter ChatInputBar and the Vue
 * ChatInput.vue). Owns the in-WebView compose field, guidance mode, image
 * attach, the 5 circle buttons, the send/stop/impersonate button, and the
 * search / selection mode variants. Uses a <textarea> (not contenteditable)
 * since the native input had no live markdown preview — this keeps caret /
 * paste / IME behaviour native and avoids contenteditable bugs.
 *
 * All user-facing strings (placeholders, search/selection labels) arrive
 * pre-localized from Flutter via setInputState() — the WebView has no i18n.
 *
 * Keyboard: the bar lifts above the on-screen keyboard using window
 * .visualViewport (mobile) and above the native drawer using the panel inset
 * Flutter pushes. Both fold into --bottom-overlap. Desktop: visualViewport
 * never shrinks, so the keyboard path is inert.
 */

const SEND_ICONS = {
  send: 'M2.01 21L23 12 2.01 3 2 10l15 2-15 2z',
  stop: 'M6 6h12v12H6z',
  confirm: 'M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z',
  impersonate:
    'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 3c1.66 0 3 1.34 3 3s-1.34 3-3 3-3-1.34-3-3 1.34-3 3-3zm0 14.2c-2.5 0-4.71-1.28-6-3.22.03-1.99 4-3.08 6-3.08 1.99 0 5.97 1.09 6 3.08-1.29 1.94-3.5 3.22-6 3.22z',
};
const EYE_ICONS = {
  // visibility_off (hide)
  hide: 'M12 7c2.76 0 5 2.24 5 5 0 .65-.13 1.26-.36 1.83l2.92 2.92c1.51-1.26 2.7-2.89 3.43-4.75-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16C10.74 7.13 11.35 7 12 7zM2 4.27l2.28 2.28.46.46C3.08 8.3 1.78 10.02 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84l.42.42L19.73 22 21 20.73 3.27 3 2 4.27zM7.53 9.8l1.55 1.55c-.05.21-.08.43-.08.65 0 1.66 1.34 3 3 3 .22 0 .44-.03.65-.08l1.55 1.55c-.67.33-1.41.53-2.2.53-2.76 0-5-2.24-5-5 0-.79.2-1.53.53-2.2zm4.31-.78l3.15 3.15.02-.16c0-1.66-1.34-3-3-3l-.17.01z',
  // visibility (unhide)
  show: 'M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8a3 3 0 1 0 0 6 3 3 0 0 0 0-6z',
};

export class InputController {
  constructor(bridge) {
    this.bridge = bridge;
    this._send = (name, args) => bridge._sendToFlutter(name, args);

    this._ready = false;
    this._guidanceMode = false;
    this._imageDataUrl = null;
    this._isGenerating = false;
    this._isSelectionMode = false;
    this._showSearch = false;
    this._enterToSend = true;
    this._virtualKeyboardSend = false;
    this._isEditing = false;
    this._isDrawerOpen = false;
    this._isQuickRepliesOpen = false;
    this._panelInset = 0; // native drawer height, pushed by Flutter
    this._kbOverlap = 0; // visualViewport keyboard overlap (fallback source)
    this._kbInsetFlutter = 0; // keyboard overlap pushed by Flutter (authoritative)
    this._kbFlutterActive = false; // Flutter has taken over keyboard geometry
    this._draftDebounce = null;

    this._bar = document.getElementById('chat-input-bar');
    this._field = document.getElementById('chat-input-field');
    this._guidanceField = document.getElementById('input-guidance-field');
    this._guidanceWrap = document.getElementById('input-guidance');
    this._imgWrap = document.getElementById('input-image-preview');
    this._imgEl = document.getElementById('input-image-img');
    this._fileInput = document.getElementById('input-file');
    this._sendIcon = document.getElementById('input-send-icon');
    this._searchCount = document.getElementById('input-search-count');
    this._selCount = document.getElementById('input-sel-count');
    this._selHide = document.getElementById('input-sel-hide');
    this._selHideIcon = document.getElementById('input-sel-hide-icon');
    this._selDelete = document.getElementById('input-sel-delete');
    this._btnMagic = document.getElementById('input-btn-magic');
    this._btnGuidance = document.getElementById('input-btn-guidance');
    this._btnQuick = document.getElementById('input-btn-quick');
    this._scrollBtn = document.getElementById('scroll-to-bottom');

    if (this._bar) this._setup();
  }

  /* ---------- Flutter -> JS commands ---------- */

  /// Applies pushed input state and reveals the bar on first call.
  setInputState(opts) {
    opts = opts || {};
    if ('safeBottom' in opts) {
      document.documentElement.style.setProperty(
        '--safe-bottom', (opts.safeBottom || 0) + 'px');
    }
    if ('placeholder' in opts && this._field) {
      this._field.placeholder = opts.placeholder || '';
    }
    if ('guidancePlaceholder' in opts && this._guidanceField) {
      this._guidanceField.placeholder = opts.guidancePlaceholder || '';
    }
    if ('draft' in opts) this._setDraft(opts.draft || '');
    if ('enterToSend' in opts) this._enterToSend = !!opts.enterToSend;
    if ('virtualKeyboardSend' in opts) {
      this._virtualKeyboardSend = !!opts.virtualKeyboardSend;
      if (this._field) {
        this._field.setAttribute(
          'enterkeyhint', this._virtualKeyboardSend ? 'send' : 'enter');
      }
    }
    if ('isGenerating' in opts) this._isGenerating = !!opts.isGenerating;
    if ('isEditing' in opts) {
      this._isEditing = !!opts.isEditing;
      if (this._field) this._field.readOnly = this._isEditing;
      if (this._isEditing && this._field) this._field.blur();
    }
    if ('isDrawerOpen' in opts) this._isDrawerOpen = !!opts.isDrawerOpen;
    if ('isQuickRepliesOpen' in opts) {
      this._isQuickRepliesOpen = !!opts.isQuickRepliesOpen;
    }
    if ('isSelectionMode' in opts) this._isSelectionMode = !!opts.isSelectionMode;
    if ('showSearch' in opts) this._showSearch = !!opts.showSearch;
    if ('searchLabel' in opts && this._searchCount) {
      this._searchCount.textContent = opts.searchLabel || '';
    }
    if ('selectionLabel' in opts && this._selCount) {
      this._selCount.textContent = opts.selectionLabel || '';
    }
    if ('selectedCount' in opts) {
      const has = (opts.selectedCount || 0) > 0;
      if (this._selHide) this._selHide.classList.toggle('disabled', !has);
      if (this._selDelete) this._selDelete.classList.toggle('disabled', !has);
    }
    if ('allSelectedHidden' in opts && this._selHideIcon) {
      this._selHideIcon.setAttribute(
        'd', opts.allSelectedHidden ? EYE_ICONS.show : EYE_ICONS.hide);
    }

    this._applyMode();
    this._refreshButtons();
    this._relayout();

    this._ready = true;
    if (this._bar) {
      this._bar.classList.remove('hidden');
      this._bar.setAttribute('aria-hidden', 'false');
    }
  }

  /// Native drawer height (magic / quick-replies), pushed by Flutter. Folds
  /// into the bottom overlap so the bar sits above the native panel.
  setPanelInset(px) {
    this._panelInset = Math.max(0, px || 0);
    this._relayout();
  }

  /// On-screen keyboard overlap, pushed by Flutter from MediaQuery.viewInsets
  /// (authoritative once it fires — see chat_screen.dart _ChatBody). Flutter
  /// pushes a single predicted end-value on the rising/falling edge with
  /// [animate] true (the bar's CSS transition + the list's scrollTop ease play
  /// it out over ~250 ms, in sync with the platform keyboard), then a final
  /// exact correction with [animate] false once the inset settles. Because the
  /// value arrives already de-jittered from Flutter, we never touch the
  /// per-frame visualViewport path here, which was late/coarse on Android
  /// WebView and produced the out-of-sync, delayed slide. If Flutter never
  /// fires (viewInsets not tracking the WebView keyboard on some platform),
  /// [_kbFlutterActive] stays false and visualViewport keeps driving.
  setKeyboardInset(px, animate) {
    this._kbFlutterActive = true;
    this._kbInsetFlutter = Math.max(0, px || 0);
    this._relayout(!!animate);
  }

  clearInput() {
    if (this._field) this._field.value = '';
    if (this._guidanceField) this._guidanceField.value = '';
    this._imageDataUrl = null;
    this._guidanceMode = false;
    this._updateImagePreview();
    if (this._guidanceWrap) this._guidanceWrap.classList.add('hidden');
    this._autoGrow(this._field);
    this._refreshButtons();
    this._relayout();
  }

  blurInput() {
    if (this._field) this._field.blur();
    if (this._guidanceField) this._guidanceField.blur();
  }

  focusInput() {
    if (this._field && !this._isEditing) this._field.focus();
  }

  setScrollToBottomVisible(visible) {
    if (this._scrollBtn) this._scrollBtn.classList.toggle('hidden', !visible);
  }

  /* ---------- setup ---------- */

  _setup() {
    this._field.addEventListener('input', () => this._onInput());
    this._field.addEventListener('keydown', (e) => this._onKeyDown(e));
    this._field.addEventListener('focus', () => this._send('onInputFocus', [true]));
    this._field.addEventListener('blur', () => this._send('onInputFocus', [false]));

    this._guidanceField.addEventListener('input', () => {
      this._autoGrow(this._guidanceField);
      this._refreshButtons();
    });

    this._btnMagic.addEventListener('click', () => {
      this.blurInput();
      this._send('onMagicDrawer', []);
    });
    this._btnQuick.addEventListener('click', () => {
      this.blurInput();
      this._send('onQuickReplies', []);
    });
    this._btnGuidance.addEventListener('click', () => this._toggleGuidance());
    document.getElementById('input-btn-attach')
      .addEventListener('click', () => this._fileInput.click());
    document.getElementById('input-btn-fullscreen')
      .addEventListener('click', () =>
        this._send('onFullScreenEditor', [this._field.value]));
    document.getElementById('input-btn-send')
      .addEventListener('click', () => this._onSendButton());

    this._fileInput.addEventListener('change', (e) => this._onImagePicked(e));
    document.getElementById('input-image-remove')
      .addEventListener('click', () => {
        this._imageDataUrl = null;
        this._updateImagePreview();
        this._refreshButtons();
        this._relayout();
      });

    document.getElementById('input-sel-cancel')
      .addEventListener('click', () => this._send('onCancelSelection', []));
    this._selHide.addEventListener('click', () => {
      if (!this._selHide.classList.contains('disabled')) {
        this._send('onHideSelected', []);
      }
    });
    this._selDelete.addEventListener('click', () => {
      if (!this._selDelete.classList.contains('disabled')) {
        this._send('onDeleteSelected', []);
      }
    });
    document.getElementById('input-search-prev')
      .addEventListener('click', () => this._send('onSearchPrev', []));
    document.getElementById('input-search-next')
      .addEventListener('click', () => this._send('onSearchNext', []));
    this._scrollBtn.addEventListener('click', () =>
      this._send('onScrollToBottomTap', []));

    // Re-pad the message list whenever the bar's height changes (text growth,
    // guidance, image, mode switch).
    if (window.ResizeObserver) {
      this._ro = new ResizeObserver(() => this._relayout());
      this._ro.observe(this._bar);
    }

    // Keyboard follow via visualViewport (mobile). Inert on desktop.
    if (window.visualViewport) {
      const onVv = () => this._onViewportChange();
      window.visualViewport.addEventListener('resize', onVv);
      window.visualViewport.addEventListener('scroll', onVv);
    }
  }

  /* ---------- input events ---------- */

  _onInput() {
    this._autoGrow(this._field);
    this._refreshButtons();
    this._relayout();
    const text = this._field.value;
    clearTimeout(this._draftDebounce);
    this._draftDebounce = setTimeout(
      () => this._send('onInputDraftChanged', [text]), 500);
  }

  _onKeyDown(e) {
    if (e.key !== 'Enter' || e.isComposing) return;
    if (this._isEditing) return;
    const shouldSend = this._enterToSend
      ? (!e.shiftKey && !e.ctrlKey)
      : (e.shiftKey || e.ctrlKey);
    if (shouldSend) {
      e.preventDefault();
      this._handleSend();
    }
  }

  _onSendButton() {
    const action = this._currentAction();
    if (action === 'stop') {
      this._send('onInputStop', []);
    } else if (action === 'send') {
      this._handleSend();
    } else {
      this._send('onInputImpersonate', []);
    }
  }

  _handleSend() {
    const text = this._field.value;
    const hasImage = !!this._imageDataUrl;
    if (!text.trim() && !hasImage) return;
    const guidance =
      this._guidanceMode && this._guidanceField.value.trim()
        ? this._guidanceField.value.trim()
        : null;
    // Do NOT clear optimistically: Flutter validates prerequisites (persona /
    // API) and calls clearInput() only on a real send, so nothing is lost when
    // it shows a "no provider" modal instead.
    this._send('onInputSend', [
      JSON.stringify({ text, guidance, imageDataUrl: this._imageDataUrl || null }),
    ]);
  }

  _toggleGuidance() {
    this._guidanceMode = !this._guidanceMode;
    this._guidanceWrap.classList.toggle('hidden', !this._guidanceMode);
    if (!this._guidanceMode) {
      this._guidanceField.value = '';
    } else {
      this._guidanceField.focus();
    }
    this._refreshButtons();
    this._relayout();
  }

  _onImagePicked(e) {
    const file = e.target.files && e.target.files[0];
    e.target.value = '';
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => {
      this._imageDataUrl = ev.target.result;
      this._updateImagePreview();
      this._refreshButtons();
      this._relayout();
    };
    reader.readAsDataURL(file);
  }

  _updateImagePreview() {
    if (!this._imgWrap) return;
    if (this._imageDataUrl) {
      this._imgEl.src = this._imageDataUrl;
      this._imgWrap.classList.remove('hidden');
    } else {
      this._imgEl.removeAttribute('src');
      this._imgWrap.classList.add('hidden');
    }
  }

  _setDraft(text) {
    if (!this._field) return;
    if (this._field.value === text) return;
    this._field.value = text;
    this._autoGrow(this._field);
    this._refreshButtons();
  }

  /* ---------- view state ---------- */

  _hasContent() {
    const text = this._field ? this._field.value.trim() : '';
    const guidance = this._guidanceMode && this._guidanceField
      ? this._guidanceField.value.trim() : '';
    return !!text || !!guidance || !!this._imageDataUrl;
  }

  _currentAction() {
    if (this._isGenerating) return 'stop';
    if (this._hasContent()) return 'send';
    return 'impersonate';
  }

  _applyMode() {
    if (!this._bar) return;
    const mode = this._showSearch
      ? 'mode-search'
      : (this._isSelectionMode ? 'mode-selection' : 'mode-normal');
    this._bar.classList.remove('mode-normal', 'mode-search', 'mode-selection');
    this._bar.classList.add(mode);
  }

  _refreshButtons() {
    if (this._btnMagic) {
      this._btnMagic.classList.toggle('active', this._isDrawerOpen);
    }
    if (this._btnQuick) {
      this._btnQuick.classList.toggle('active', this._isQuickRepliesOpen);
    }
    if (this._btnGuidance) {
      this._btnGuidance.classList.toggle('active-guidance', this._guidanceMode);
    }
    if (this._sendIcon) {
      const action = this._currentAction();
      let icon = SEND_ICONS.impersonate;
      if (action === 'stop') {
        icon = SEND_ICONS.stop;
      } else if (action === 'send') {
        const mainEmpty = this._field && !this._field.value.trim();
        icon = (this._guidanceMode && mainEmpty)
          ? SEND_ICONS.confirm : SEND_ICONS.send;
      }
      this._sendIcon.setAttribute('d', icon);
    }
  }

  /* ---------- layout / keyboard ---------- */

  _autoGrow(el) {
    if (!el) return;
    el.style.height = 'auto';
    const max = el === this._guidanceField ? 80 : 150;
    el.style.height = Math.min(el.scrollHeight, max) + 'px';
  }

  _onViewportChange() {
    const vv = window.visualViewport;
    if (!vv) return;
    // Overlap = how much of the layout viewport the keyboard covers.
    const overlap = Math.max(
      0, window.innerHeight - vv.height - vv.offsetTop);
    const open = overlap > 80;
    if (overlap === this._kbOverlap) return;
    this._kbOverlap = overlap;
    // When Flutter drives the keyboard geometry, visualViewport is only kept
    // as the open/close signal for the native keyboard<->drawer swap; it must
    // not re-lay-out (it would fight / cancel Flutter's in-flight animated
    // re-pin with a late, coarse value — the very jank we're removing).
    if (!this._kbFlutterActive) this._relayout();
    this._send('onKeyboardInset', [JSON.stringify({ height: overlap, open })]);
  }

  _relayout(animate) {
    if (!this._bar) return;
    const kb = this._kbFlutterActive ? this._kbInsetFlutter : this._kbOverlap;
    const overlap = Math.max(kb, this._panelInset);
    const root = document.documentElement.style;
    // Bar position: fixed against the full viewport, so it must clear the whole
    // keyboard/drawer overlap. Driven per keyboard edge from Flutter → smooth.
    root.setProperty('--bottom-overlap', overlap + 'px');
    this._bar.classList.toggle('kb-open', overlap > 0);
    const barHeight = this._bar.offsetHeight;
    root.setProperty('--input-bar-height', barHeight + 'px');
    // List scroll area must reserve the FULL bottom overlap (keyboard + native
    // drawer), same as the bar. Glaze parity: its WebView is full-screen and the
    // on-screen keyboard OVERLAYS it (Capacitor `overlays-content`), so Glaze
    // pushes the messages container up by the keyboard height and reserves that
    // space in the scroll area (ChatView.vue: container `marginBottom`, list
    // `padding-bottom`). Here the WebView is likewise never resized —
    // `resizeToAvoidBottomInset: false` keeps the Flutter body (and thus the
    // WebView) full-height and lets the keyboard overlay it — so `adjustResize`
    // does NOT shrink the viewport. If the list padding left the keyboard term
    // out, the bottom `keyboardHeight` of the chat would sit behind the keyboard
    // and never reserve space (the "no padding" bug). Fold the whole overlap in;
    // #chat-container's clientHeight is unchanged (containerHeightDiff = 0 in
    // setBottomPadding), so the re-pin is a clean `scrollTop += paddingDiff`.
    const listOverlap = overlap;
    if (this.bridge && typeof this.bridge.setBottomPadding === 'function') {
      this.bridge.setBottomPadding(barHeight + listOverlap, !!animate);
    }
  }
}
