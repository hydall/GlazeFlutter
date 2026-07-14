/* Extracted from ../bridge.legacy.js. Keep public behavior stable. */

import { GenTimer } from './gen_timer.js';
import { ImgGenTimer } from './imggen_timer.js';
import { MessageUpdateBatcher } from './message_update_batcher.js';
import { SelectionManager } from './selection_manager.js';
import { EditController } from './edit_controller.js';
import { SwipeGestureHandler } from './swipe_gesture_handler.js';
import { InteractionDispatch } from './interaction_dispatch.js';
import { PanelHost } from './panel_host.js';
import { InputController } from './chat_input_controller.js';
import { ICON } from '../renderer/icon_library.js';

export class Bridge {
  constructor(renderer, virtualList) {
    this.renderer = renderer;
    this.virtualList = virtualList;
    this._pendingRequests = new Map();
    this._requestCounter = 0;
    this.isGenerating = false;
    this.isGeneratingImage = false;
    this.isPostGenRunning = false;
    this._genTimer = new GenTimer(renderer);
    this._imgGenTimer = new ImgGenTimer();
    this._updateBatcher = new MessageUpdateBatcher();
    this._selectionManager = new SelectionManager((name, args) => this._sendToFlutter(name, args));
    this._editController = new EditController((name, args) => this._sendToFlutter(name, args));
    this._interaction = new InteractionDispatch(this);
    this._charName = null;
    this._personaName = null;
    this._charAvatarUrl = null;
    this._personaAvatarUrl = null;
    this.batterySaver = false;
    this.disableSwipeRegeneration = false;
    renderer.selectionManager = this._selectionManager;
    this._swipeHandler = new SwipeGestureHandler(
      (name, args) => this._sendToFlutter(name, args),
      () => this.virtualList.container,
      () => this.isGenerating,
      () => this.disableSwipeRegeneration,
    );
    this._headerReady = false;
    this._headerScrollHidden = false;
    this._setupHeaderControls();
    this._input = new InputController(this);
    this._setupScrollListener();
    this._setupInteractionListener();
    this._setupGlazeRequestRelay();
    this._setupImageClickForward();
    this._swipeHandler.setup();
  }

  /* ---------- Identity (active char / persona) ---------- */
  setIdentity(opts) {
    opts = opts || {};
    if ('charName' in opts) this._charName = opts.charName || null;
    if ('personaName' in opts) this._personaName = opts.personaName || null;
    if ('charAvatarUrl' in opts) this._charAvatarUrl = opts.charAvatarUrl || null;
    if ('personaAvatarUrl' in opts) this._personaAvatarUrl = opts.personaAvatarUrl || null;
    this._refreshIdentityDom();
  }

  _refreshIdentityDom() {
    const sections = document.querySelectorAll('.message-section.user, .message-section.char');
    sections.forEach(section => {
      const isUser = section.classList.contains('user');
      const stored = section.dataset.personaName || '';
      const storedPersonaName = stored === 'You' ? '' : stored;
      // Per-message stored persona wins; otherwise use the active identity.
      const newName = isUser
        ? (storedPersonaName || this._personaName || 'You')
        : (this._charName || stored || 'Character');
      const newAvatarUrl = isUser ? this._personaAvatarUrl : this._charAvatarUrl;

      const label = section.querySelector('.msg-name-label');
      if (label) label.textContent = newName;

      const avatar = section.querySelector('.msg-avatar');
      if (!avatar) return;
      const existingImg = avatar.querySelector('img');
      if (newAvatarUrl) {
        if (existingImg) {
          if (existingImg.src !== newAvatarUrl) existingImg.src = newAvatarUrl;
          existingImg.alt = newName;
        } else {
          avatar.textContent = '';
          const img = document.createElement('img');
          img.src = newAvatarUrl;
          img.alt = newName;
          avatar.appendChild(img);
        }
      } else {
        if (existingImg) existingImg.remove();
        avatar.textContent = (newName.charAt(0) || '?').toUpperCase();
      }
    });
  }

  /* ---------- Chat header (avatar + name + session) ---------- */

  /// Populates the in-WebView header. Called from Flutter whenever the active
  /// character, avatar, session name or safe-area inset changes. Once data has
  /// arrived the header is revealed (the initial `hidden` class is dropped).
  setHeader(opts) {
    opts = opts || {};
    const header = document.getElementById('chat-header');
    if (!header) return;
    if ('safeTop' in opts) {
      document.documentElement.style.setProperty(
        '--safe-top', (opts.safeTop || 0) + 'px');
    }
    const name = opts.charName || '';
    const nameEl = document.getElementById('chat-header-name');
    const sessEl = document.getElementById('chat-header-session');
    const avEl = document.getElementById('chat-header-avatar');
    if (nameEl) nameEl.textContent = name;
    if (sessEl && 'sessionName' in opts) sessEl.textContent = opts.sessionName || '';
    if (avEl) {
      const url = 'charAvatarUrl' in opts ? opts.charAvatarUrl : this._charAvatarUrl;
      if (url) {
        avEl.style.backgroundImage = `url("${url}")`;
        avEl.textContent = '';
        avEl.style.color = '';
        avEl.style.backgroundColor = '';
      } else {
        let color = opts.charColor || null;
        if (color && color.charAt(0) !== '#') color = '#' + color;
        avEl.style.backgroundImage = 'none';
        avEl.textContent = name ? name.charAt(0).toUpperCase() : '?';
        avEl.style.color = color || 'var(--vk-blue)';
        // 8-digit hex alpha ≈ 0.2, mirroring the native avatar tint.
        avEl.style.backgroundColor = color
          ? color + '33'
          : 'rgba(var(--vk-blue-rgb), 0.2)';
      }
    }
    this._headerReady = true;
    header.setAttribute('aria-hidden', 'false');
    if (!this._headerScrollHidden) header.classList.remove('hidden');
  }

  /// Toggles the header out of view while the native search bar is shown
  /// (the search text input stays native to keep the platform keyboard).
  setSearchMode(on) {
    const header = document.getElementById('chat-header');
    if (header) header.classList.toggle('search-mode', !!on);
  }

  /* ---------- Chat input bar (delegates to InputController) ---------- */
  setInputState(opts) { this._input?.setInputState(opts); }
  setPanelInset(px) { this._input?.setPanelInset(px); }
  setKeyboardInset(px, animate) { this._input?.setKeyboardInset(px, animate); }
  clearInput() { this._input?.clearInput(); }
  blurInput() { this._input?.blurInput(); }
  focusInput() { this._input?.focusInput(); }

  /// Fans a scroll-to-bottom visibility change out to both Flutter (legacy
  /// listeners) and the in-WebView scroll button owned by the InputController.
  _emitScrollBtnVisible(visible) {
    this._sendToFlutter('onScrollToBottomVisibility', [visible]);
    this._input?.setScrollToBottomVisible(visible);
  }

  _setupHeaderControls() {
    const back = document.getElementById('chat-header-back');
    const search = document.getElementById('chat-header-search');
    if (back) {
      back.addEventListener('click', () => this._sendToFlutter('onHeaderBack', []));
    }
    if (search) {
      search.addEventListener('click', () => this._sendToFlutter('onHeaderSearch', []));
    }
  }

  _applyHeaderScrollHidden(hidden) {
    this._headerScrollHidden = hidden;
    if (!this._headerReady) return;
    const header = document.getElementById('chat-header');
    if (header) header.classList.toggle('hidden', hidden);
  }

  setGenerating(value) {
    this.isGenerating = !!value;
    this._syncGenerationActivity();
  }

  setPostGenRunning(value) {
    this.isPostGenRunning = !!value;
    this._syncGenerationActivity();
  }

  _syncGenerationActivity() {
    if (this.isGenerating || this.isPostGenRunning) {
      this._genTimer.start();
    } else {
      this._genTimer.stop();
    }
  }

  /* ---------- Flutter transport ---------- */
  _sendToFlutter(name, args) {
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler(name, ...args);
    }
  }

  _requestToFlutter(name, args, timeoutMs = 60000) {
    return new Promise((resolve, reject) => {
      const requestId = `${name}_${++this._requestCounter}`;
      const timer = setTimeout(() => {
        this._pendingRequests.delete(requestId);
        reject(new Error(`Bridge request "${name}" timed out after ${timeoutMs}ms`));
      }, timeoutMs);
      this._pendingRequests.set(requestId, { resolve, reject, timer });
      this._sendToFlutter(name, [requestId, ...args]);
    });
  }

  _setupGlazeRequestRelay() {
    window.addEventListener('message', async (e) => {
      const data = e.data || {};
      if (!data || data.type !== 'glaze:request') return;
      if (!e.source) return;
      try {
        const result = await this._callGlazeBridge({
          id: data.id,
          method: data.method,
          params: data.params || {},
          context: data.context || {},
        });
        e.source.postMessage({ type: 'glaze:response', id: data.id, ok: true, result }, '*');
      } catch (error) {
        e.source.postMessage({
          type: 'glaze:response',
          id: data.id,
          ok: false,
          error: { message: String(error && error.message ? error.message : error) },
        }, '*');
      }
    });
  }

  async _callGlazeBridge(request) {
    if (!window.flutter_inappwebview || !window.flutter_inappwebview.callHandler) {
      throw new Error('Flutter bridge is not available');
    }
    const response = await window.flutter_inappwebview.callHandler('glazeBridge', request);
    if (response && response.ok === false) {
      const error = response.error || {};
      throw new Error(error.message || 'Glaze bridge error');
    }
    return response && Object.prototype.hasOwnProperty.call(response, 'result')
      ? response.result
      : response;
  }

  _resolveRequest(requestId, result) {
    const pending = this._pendingRequests.get(requestId);
    if (!pending) return;
    clearTimeout(pending.timer);
    this._pendingRequests.delete(requestId);
    pending.resolve(result);
  }

  _rejectRequest(requestId, error) {
    const pending = this._pendingRequests.get(requestId);
    if (!pending) return;
    clearTimeout(pending.timer);
    this._pendingRequests.delete(requestId);
    pending.reject(new Error(error));
  }

  /* ---------- Scroll / load-more ---------- */
  _setupScrollListener() {
    let loadMoreCooldown = false;
    let lastLoadTop = 0;
    let lastShowScrollToBottom = null;
    // Header hide-on-scroll (ported from Glaze/src/core/services/ui.js initHeaderScroll)
    let headerLastTop = 0;
    let headerHidden = false;
    let ticking = false;
    const container = this.virtualList.container;

    const emitScrollToBottomVisibility = () => {
      const distanceFromBottom =
        container.scrollHeight - container.scrollTop - container.clientHeight;
      // Mirror Vue ChatView.onScroll(): button appears past 100px from bottom.
      const show = distanceFromBottom > 100;
      if (lastShowScrollToBottom === show) return;
      lastShowScrollToBottom = show;
      this._emitScrollBtnVisible(show);
    };

    const updateHeader = () => {
      ticking = false;
      const st = container.scrollTop;
      // Skip when generating or at top/bottom bounds.
      if (this.isGenerating) {
        headerLastTop = st <= 0 ? 0 : st;
        return;
      }
      if (st < 0 || st + container.clientHeight > container.scrollHeight) {
        headerLastTop = st <= 0 ? 0 : st;
        return;
      }
      if (st > headerLastTop + 3 && st > 50) {
        if (!headerHidden) {
          headerHidden = true;
          this._applyHeaderScrollHidden(true);
          this._sendToFlutter('onHeaderScroll', [true]);
        }
      } else if (st < headerLastTop - 3) {
        if (headerHidden) {
          headerHidden = false;
          this._applyHeaderScrollHidden(false);
          this._sendToFlutter('onHeaderScroll', [false]);
        }
      }
      headerLastTop = st <= 0 ? 0 : st;
    };

    container.addEventListener('scroll', () => {
      // Load-more on upward scroll near top.
      if (!loadMoreCooldown && !this._suppressLoadMore) {
        const st = container.scrollTop;
        const scrollingUp = st < lastLoadTop;
        lastLoadTop = st;
        if (scrollingUp && this.virtualList.isNearTop(500)) {
          loadMoreCooldown = true;
          this._sendToFlutter('onLoadMore', []);
          setTimeout(() => { loadMoreCooldown = false; }, 500);
        }
      }
      // Header hide via rAF throttling.
      if (!ticking) {
        ticking = true;
        requestAnimationFrame(updateHeader);
      }
      emitScrollToBottomVisibility();
    }, { passive: true });

    requestAnimationFrame(emitScrollToBottomVisibility);
  }

  /* ---------- Interaction dispatch ---------- */
  _setupInteractionListener() {
    document.addEventListener('click', (e) => this._interaction.handleClick(e));

    document.addEventListener('selectionchange', () => this._selectionManager.handleSelectionChange());

    document.addEventListener('contextmenu', (e) => this._selectionManager.handleContextMenu(e));
  }

  _extractText(section) {
    const host = section.querySelector('.msg-body .message-content');
    if (host && host.shadowRoot) {
      const root = host.shadowRoot.querySelector('.glaze-message');
      if (root) return root.textContent || '';
    }
    return section.dataset.rawText || '';
  }

  /* ---------- Loading screen ---------- */
  _hideLoadingScreen() {
    const loading = document.getElementById('loading-screen');
    if (loading) {
      loading.style.opacity = '0';
      setTimeout(() => loading.remove(), 200);
    }
  }

  _showLoadingScreen() {
    let loading = document.getElementById('loading-screen');
    if (!loading) {
      loading = document.createElement('div');
      loading.id = 'loading-screen';
      loading.textContent = 'Loading...';
      document.body.insertBefore(loading, document.body.firstChild);
    }
    loading.style.opacity = '1';
    loading.style.display = 'flex';
  }

  /* ---------- Message list API ---------- */
  setMessages(messagesJson, preserveScroll = false) {
    this.flush();
    this._suppressLoadMore = true;
    // When re-rendering in place (e.g. a preset switch changes display regexes),
    // remember the current reading position so the batch replace below doesn't
    // yank the chat back to the top/bottom.
    const anchor = preserveScroll ? this.virtualList.captureAnchor() : null;
    this._panelHost?.closeAll();
    const container = document.getElementById('chat-container') || document.body;
    if (![...container.classList].some(c => c.startsWith('layout-'))) {
      container.classList.add('layout-default');
    }

    this.renderer.resetDateTracking();
    const messages = JSON.parse(messagesJson);

    const ids = [];
    const elements = [];
    for (const msg of messages) {
      const rendered = this.renderer.renderMessage(msg);
      for (const el of rendered) {
        const id = el.dataset.messageId || `__date_${el.dataset.dateSeparator || Date.now()}`;
        ids.push(id);
        elements.push(el);
      }
    }

    this.virtualList.setMessagesBatch(ids, elements);
    if (anchor) this.virtualList.restoreAnchor(anchor);
    this._hideLoadingScreen();
    this._imgGenTimer.ensureRunning();
    setTimeout(() => { this._suppressLoadMore = false; }, 1000);
  }

  appendMessage(messageJson) {
    this.flush();
    const msg = JSON.parse(messageJson);
    const rendered = this.renderer.renderMessage(msg);
    for (const el of rendered) {
      const id = el.dataset.messageId || `__date_${el.dataset.dateSeparator || Date.now()}`;
      this.virtualList.append(id, el);
    }
    this.virtualList.scrollToBottom();
    this._imgGenTimer.ensureRunning();
  }

  appendMessages(messagesJson) {
    this.flush();
    const messages = JSON.parse(messagesJson);
    messages.forEach(msg => {
      const rendered = this.renderer.renderMessage(msg);
      for (const el of rendered) {
        const id = el.dataset.messageId || `__date_${el.dataset.dateSeparator || Date.now()}`;
        this.virtualList.append(id, el);
      }
    });
    this._imgGenTimer.ensureRunning();
  }

  prependMessages(messagesJson) {
    this.flush();
    this._suppressLoadMore = true;
    const messages = JSON.parse(messagesJson);
    const scrollBefore = this.virtualList.container.scrollHeight;
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i];
      const rendered = this.renderer.renderMessage(msg);
      for (let j = rendered.length - 1; j >= 0; j--) {
        const el = rendered[j];
        const id = el.dataset.messageId || `__date_${el.dataset.dateSeparator || Date.now()}`;
        this.virtualList.prepend(id, el);
      }
    }
    const scrollAfter = this.virtualList.container.scrollHeight;
    this.virtualList.container.scrollTop += scrollAfter - scrollBefore;
    this._hideLoadingScreen();
    setTimeout(() => { this._suppressLoadMore = false; }, 500);
  }

  updateMessage(messageJson) {
    const msg = JSON.parse(messageJson);
    this._updateBatcher.enqueue(msg.id, () => this._executeUpdateMessage(msg));
  }

  _executeUpdateMessage(msg) {
    const section = document.querySelector(`[data-message-id="${msg.id}"]`);
    if (!section) return;

    const animate = !!msg.swipeDirection;
    if (msg.swipeDirection) section.dataset.swipeDirection = msg.swipeDirection;

    if (msg.reasoning) section.dataset.reasoning = msg.reasoning;
    else if (msg.reasoning === null || msg.reasoning === '') delete section.dataset.reasoning;

    if (msg.text != null) section.dataset.rawText = msg.text;

    if (msg.isError !== undefined) section.classList.toggle('error', !!msg.isError);

    const isUser = section.classList.contains('user');
    this.renderer.updateMessageContent(
      section,
      msg.text != null ? msg.text : (section.dataset.rawText || ''),
      msg.reasoning ?? null,
      isUser,
      !!msg.isTyping,
      animate,
    );
    this._imgGenTimer.ensureRunning();

    if (msg.isHidden !== undefined) {
      section.classList.toggle('msg-hidden', !!msg.isHidden);
    }

    if (msg.swipeIndex !== undefined) section.dataset.swipeId = String(msg.swipeIndex);
    if (msg.swipeTotal !== undefined) section.dataset.swipeTotal = String(msg.swipeTotal);
    if (msg.agentSwipeIndex !== undefined) section.dataset.agentSwipeId = String(msg.agentSwipeIndex);
    if (msg.agentSwipeTotal !== undefined) section.dataset.agentSwipeTotal = String(msg.agentSwipeTotal);
    if (msg.greetingTotal !== undefined) section.dataset.greetingTotal = String(msg.greetingTotal);

    // Restore data-is-last on char sections after generation ends.
    // setLastMessage(null) clears this flag at generation start; without
    // re-applying it here, the swipe gesture handler sees isLast=false and
    // blocks the left-swipe-to-regenerate gesture on subsequent swipes.
    if (msg.isLast !== undefined && !section.classList.contains('user')) {
      if (msg.isLast) section.dataset.isLast = 'true';
      else delete section.dataset.isLast;
    }

    this._syncMessageControls(section, msg);

    this.renderer.updateMessageMeta(section, msg);

    // Follow the bottom while a message streams in — ported from Vue
    // ChatView.smartScroll() invoked on every generation chunk. Gated on the
    // typing flag (the streamed message) and suppressed during search so the
    // active match stays in view. The pin gate inside smartScroll keeps it from
    // yanking a user who scrolled up.
    if (msg.isTyping && !(this.renderer && this.renderer.searchQuery)) {
      this.virtualList.smartScroll();
    }
  }

  flush() { this._updateBatcher.flush(); }

  _syncMessageControls(section, msg) {
    const center = section.querySelector('.msg-center-controls');
    if (!center) return;

    const isChar = section.classList.contains('char');
    const isEditing = section.classList.contains('editing');
    const isLast = section.dataset.isLast === 'true';
    const isError = msg.isError !== undefined ? !!msg.isError : section.classList.contains('error');
    const isGenerating = msg.isGenerating !== undefined ? !!msg.isGenerating : !!this.isGenerating;
    const swipeIndex = msg.swipeIndex !== undefined ? msg.swipeIndex : parseInt(section.dataset.swipeId || '0', 10);
    const swipeTotal = msg.swipeTotal !== undefined ? msg.swipeTotal : parseInt(section.dataset.swipeTotal || '0', 10);
    const agentSwipeIndex = msg.agentSwipeIndex !== undefined ? msg.agentSwipeIndex : parseInt(section.dataset.agentSwipeId || '0', 10);
    const agentSwipeTotal = msg.agentSwipeTotal !== undefined ? msg.agentSwipeTotal : parseInt(section.dataset.agentSwipeTotal || '0', 10);
    const agentSwipeFinalCount = msg.agentSwipeFinalCount !== undefined ? msg.agentSwipeFinalCount : 0;
    const greetingIndex = msg.greetingIndex !== undefined ? msg.greetingIndex : 0;
    const greetingTotal = msg.greetingTotal !== undefined ? msg.greetingTotal : parseInt(section.dataset.greetingTotal || '0', 10);
    const messageIndex = parseInt(section.dataset.messageIndex || '-1', 10);
    const hasSwipes = isChar && swipeTotal > 1;
    const hasAgentSwipes = isChar && agentSwipeFinalCount > 1;
    const hasGreetings = isChar && messageIndex === 0 && greetingTotal > 1;
    const showRegen = ((!isChar && isLast) || isError) && !isGenerating && !isEditing;

    center.innerHTML = '';

    if (hasSwipes) {
      center.appendChild(this.renderer._createSwitcher(section.dataset.messageId, swipeIndex || 0, swipeTotal, 'swipe'));
    } else if (hasGreetings) {
      center.appendChild(this.renderer._createSwitcher(section.dataset.messageId, greetingIndex || 0, greetingTotal, 'greeting'));
    }

    // Nested swipes: blue sub-swipe switcher.
    if (hasAgentSwipes) {
      center.appendChild(this.renderer._createSwitcher(section.dataset.messageId, agentSwipeIndex || 0, agentSwipeTotal, 'agent-swipe'));
    }

    if (isChar && isLast && !isGenerating && !isEditing) {
      const guided = document.createElement('div');
      guided.className = 'msg-guided-swipe-btn';
      guided.dataset.action = 'toggle-guided';
      guided.dataset.messageId = section.dataset.messageId;
      guided.title = 'Guided swipe';
      guided.innerHTML = ICON.guided;
      center.appendChild(guided);
    }

    if (isChar && isLast && isGenerating) {
      const stop = document.createElement('button');
      stop.className = 'stop-btn';
      stop.dataset.action = 'stop';
      stop.dataset.messageId = section.dataset.messageId;
      stop.title = 'Stop';
      stop.innerHTML = ICON.stop;
      center.appendChild(stop);
    }

    if (showRegen) {
      const regen = document.createElement('div');
      regen.className = 'msg-regenerate';
      if (hasSwipes || hasGreetings || hasAgentSwipes) regen.classList.add('icon-only');
      regen.dataset.action = 'regenerate';
      regen.dataset.messageId = section.dataset.messageId;
      regen.dataset.mode = 'magic';
      regen.title = 'Regenerate';
      regen.innerHTML = ICON.regen;
      if (!hasSwipes && !hasGreetings && !hasAgentSwipes) {
        const span = document.createElement('span');
        span.textContent = 'Regenerate';
        regen.appendChild(span);
      }
      center.appendChild(regen);
    }
  }

  setLastMessage(newLastId) {
    // Clear previous last — char or user
    const prevLast = document.querySelector('.message-section[data-is-last="true"]');
    if (prevLast) {
      delete prevLast.dataset.isLast;
      const center = prevLast.querySelector('.msg-center-controls');
      if (center) {
        center.querySelector('.msg-regenerate')?.remove();
        center.querySelector('.msg-guided-swipe-btn')?.remove();
        center.querySelector('.stop-btn')?.remove();
      }
    }
    if (!newLastId) return;
    const newLast = document.querySelector(`[data-message-id="${newLastId}"]`);
    if (!newLast) return;
    newLast.dataset.isLast = 'true';

    // For user messages: inject regen button directly into DOM
    if (newLast.classList.contains('user')) {
      let center = newLast.querySelector('.msg-center-controls');
      if (!center) {
        center = document.createElement('div');
        center.className = 'msg-center-controls';
        const footer = newLast.querySelector('.msg-footer');
        if (footer) footer.appendChild(center);
      }
      if (!center.querySelector('.msg-regenerate')) {
        const regen = document.createElement('div');
        regen.className = 'msg-regenerate';
        regen.dataset.action = 'regenerate';
        regen.dataset.messageId = newLastId;
        regen.dataset.mode = 'magic';
        regen.innerHTML = (typeof ICON !== 'undefined' && ICON.regen) ? ICON.regen : '<svg viewBox="0 0 24 24"><path d="M17.65 6.35C16.2 4.9 14.21 4 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08c-.82 2.33-3.04 4-5.65 4-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/></svg>';
        const span = document.createElement('span');
        span.textContent = 'Regenerate';
        regen.appendChild(span);
        center.appendChild(regen);
      }
    }
    // For char messages: renderer rebuilds controls on next render; flag is enough.
  }

  removeMessage(messageId) {
    this.flush();
    if (this._panelHost) {
      for (const [panelId, panel] of [...this._panelHost._panels.entries()]) {
        if (panel.messageId === messageId) this._panelHost.close(panelId);
      }
    }
    const el = document.querySelector(`[data-message-id="${messageId}"]`);
    if (el && this.renderer) {
      this.renderer.animateRemoveSection(el, () => this.virtualList.remove(messageId));
    } else {
      this.virtualList.remove(messageId);
    }
  }

  clearAll() {
    this.flush();
    this._showLoadingScreen();
    this._panelHost?.closeAll();
    this.virtualList.clear();
  }

  scrollToBottom(behavior = 'auto') {
    this.virtualList.scrollToBottom(behavior);
    requestAnimationFrame(() => {
      this._emitScrollBtnVisible(false);
    });
  }
  scrollToMessage(messageId, highlight = false) { this.virtualList.scrollToMessage(messageId, highlight); }

  setSearch(query, activeIndex) { this.renderer.setSearch(query, activeIndex); }

  setChatFont(fontFamily, fontDataUrl, fontSize, letterSpacing) {
    const root = document.documentElement;
    if (fontSize != null) {
      root.style.setProperty('--font-size', fontSize + 'px');
      root.style.setProperty('--chat-font-size', fontSize + 'px');
    }
    if (letterSpacing != null) {
      root.style.setProperty('--letter-spacing', letterSpacing + 'px');
      root.style.setProperty('--chat-letter-spacing', letterSpacing + 'px');
    }

    let fontFace = document.getElementById('custom-font-face');
    if (fontDataUrl) {
      if (!fontFace) {
        fontFace = document.createElement('style');
        fontFace.id = 'custom-font-face';
        document.head.appendChild(fontFace);
      }
      fontFace.textContent = `@font-face { font-family: '${fontFamily || 'CustomChatFont'}'; src: url('${fontDataUrl}'); font-display: swap; }`;
      root.style.setProperty('--font-family', `'${fontFamily || 'CustomChatFont'}', sans-serif`);
    } else {
      if (fontFace) fontFace.remove();
      if (fontFamily) root.style.setProperty('--font-family', fontFamily);
      else root.style.removeProperty('--font-family');
    }
  }

  _normalizeLayout(layout) {
    const raw = String(layout || '').trim().toLowerCase();
    return (raw === 'bubble' || raw === 'bubbles') ? 'bubble' : 'default';
  }

  applyTheme(themeJson) {
    const theme = JSON.parse(themeJson);
    const container = document.getElementById('chat-container') || document.body;

    for (const [key, value] of Object.entries(theme)) {
      if (key === 'chat-layout') {
        const layout = this._normalizeLayout(value);
        container.classList.remove('layout-bubble', 'layout-default');
        container.classList.add(`layout-${layout}`);
        document.querySelectorAll('.message-section').forEach(el => {
          el.classList.remove('layout-bubble', 'layout-default');
          el.classList.add(`layout-${layout}`);
        });
        continue;
      }
      document.documentElement.style.setProperty(`--${key}`, value);
    }

    const toggleClass = (className, enabled) => {
      container.classList.toggle(className, !!enabled);
    };
    toggleClass('hide-user-avatar', theme['show-user-avatar'] === '0');
    toggleClass('hide-char-avatar', theme['show-char-avatar'] === '0');
    toggleClass('hide-user-name', theme['show-user-name'] === '0');
    toggleClass('hide-char-name', theme['show-char-name'] === '0');
  }

  setBottomPadding(px, animate = false) {
    const container = document.getElementById('chat-container') || document.body;
    const prevPadding = parseFloat(container.style.paddingBottom) || 0;
    const paddingDiff = px - prevPadding;
    if (Math.abs(paddingDiff) < 0.1) return;

    // Ported from Vue ChatView.updateContentPadding(). The chat container is a
    // FIXED full-screen viewport (`resizeToAvoidBottomInset: false`, the keyboard
    // overlays it) so its clientHeight never changes — Vue's `containerHeightDiff`
    // term is 0 here and the scroll adjustment collapses to the padding delta.
    // We shift scrollTop by that delta so the content the user is reading stays
    // anchored to the rising/falling input bar when the keyboard / magic drawer /
    // input height changes — and so more-recent messages slide up into view above
    // the keyboard. This must happen whether or not the chat is parked at the
    // bottom; the at-bottom branch is just the numerically-clean equivalent of
    // `+= paddingDiff` that avoids float drift at the very end of the list.
    const wasAtBottom =
      container.scrollHeight - container.scrollTop - container.clientHeight < 5;

    // Lock the virtual-scroll window logic while we programmatically re-pin so
    // the inset-follow does not fight onContainerScroll / the pin tracker.
    const vl = this.virtualList;
    if (vl) vl.isProgrammaticScrolling = true;
    // Any in-flight inset animation is stale now (a newer target arrived).
    if (this._insetAnim) {
      cancelAnimationFrame(this._insetAnim);
      this._insetAnim = null;
    }

    const unlockSoon = () => {
      clearTimeout(this._bottomPadUnlockTimer);
      this._bottomPadUnlockTimer = setTimeout(() => {
        if (vl) vl.isProgrammaticScrolling = false;
      }, 120);
    };

    const pingVisibility = () => {
      const distanceFromBottom =
        container.scrollHeight - container.scrollTop - container.clientHeight;
      this._emitScrollBtnVisible(distanceFromBottom > 100);
    };

    // Instant path (init / app-resume reconcile): apply padding + re-pin in one
    // frame. Reading scrollHeight forces a synchronous layout flush so the new
    // padding is reflected before we adjust the offset.
    if (!animate) {
      container.style.paddingBottom = px + 'px';
      if (wasAtBottom) {
        container.scrollTop = container.scrollHeight - container.clientHeight;
      } else {
        container.scrollTop += paddingDiff;
      }
      unlockSoon();
      requestAnimationFrame(pingVisibility);
      return;
    }

    // Animated path (keyboard / drawer transition): Flutter pushes only the end
    // inset once — we ease scrollTop toward it inside JS instead of jumping. The
    // padding change is a single relayout; the per-frame work is scrollTop only
    // (compositor scroll, no message-list relayout — same cost as a finger drag).
    //
    // endScroll = startScroll + paddingDiff holds in both directions: opening
    // (paddingDiff > 0) slides content up above the rising bar; closing
    // (paddingDiff < 0) slides it down after the descending bar.
    const opening = paddingDiff > 0;
    // Opening: grow padding NOW so there is room to scroll into. Closing: keep
    // the larger padding until the slide ends, else the browser clamps scrollTop
    // to the smaller max and the content jumps (the very teleport we're killing).
    if (opening) container.style.paddingBottom = px + 'px';

    const startScroll = container.scrollTop;
    const endScroll = Math.max(0, startScroll + paddingDiff);
    const duration = 250;
    const t0 = performance.now();
    const ease = (t) => 1 - Math.pow(1 - t, 3); // easeOutCubic ≈ decelerate

    const step = (now) => {
      const t = Math.min(1, (now - t0) / duration);
      container.scrollTop = startScroll + (endScroll - startScroll) * ease(t);
      if (t < 1) {
        this._insetAnim = requestAnimationFrame(step);
        return;
      }
      this._insetAnim = null;
      if (!opening) container.style.paddingBottom = px + 'px';
      if (wasAtBottom) {
        container.scrollTop = container.scrollHeight - container.clientHeight;
      }
      unlockSoon();
      pingVisibility();
    };
    this._insetAnim = requestAnimationFrame(step);
  }

  setTopPadding(px) {
    const container = document.getElementById('chat-container') || document.body;
    container.style.paddingTop = px + 'px';
  }

  /* ---------- Overlay blur regions (Flutter glass over the WebView) ----------
   * Flutter's BackdropFilter cannot sample the platform view, so the header /
   * input-bar glass widgets can't blur the messages scrolling under them.
   * Flutter mirrors their rects here; each region becomes a fixed
   * backdrop-filter strip that blurs the page content (the messages) while the
   * global background stays on the Flutter side (the page is transparent, so
   * there is nothing else to blur). No tint/noise — those stay in Flutter. */
  setOverlayBlurRegions(regions) {
    let parsed;
    try {
      parsed = typeof regions === 'string' ? JSON.parse(regions) : regions;
    } catch (_) {
      parsed = [];
    }
    this._overlayBlurRegions = Array.isArray(parsed) ? parsed : [];
    this._renderOverlayBlurRegions();
  }

  _renderOverlayBlurRegions() {
    const regions = this.batterySaver ? [] : (this._overlayBlurRegions || []);
    let layer = document.getElementById('overlay-blur-layer');
    if (regions.length === 0) {
      if (layer) layer.remove();
      return;
    }
    if (!layer) {
      layer = document.createElement('div');
      layer.id = 'overlay-blur-layer';
      document.body.appendChild(layer);
    }
    const seen = new Set();
    for (const r of regions) {
      if (!r || r.id == null) continue;
      const id = String(r.id);
      seen.add(id);
      let el = layer.querySelector(`[data-region-id="${CSS.escape(id)}"]`);
      if (!el) {
        el = document.createElement('div');
        el.className = 'overlay-blur-region';
        el.dataset.regionId = id;
        layer.appendChild(el);
      }
      el.style.left = (r.x || 0) + 'px';
      el.style.top = (r.y || 0) + 'px';
      el.style.width = (r.w || 0) + 'px';
      el.style.height = (r.h || 0) + 'px';
      el.style.borderRadius = (r.r || 0) + 'px';
    }
    for (const el of Array.from(layer.children)) {
      if (!seen.has(el.dataset.regionId)) el.remove();
    }
  }

  applyLayout(layout) {
    const normalized = this._normalizeLayout(layout);
    const container = document.getElementById('chat-container') || document.body;
    container.classList.remove('layout-bubble', 'layout-default');
    container.classList.add(`layout-${normalized}`);
    document.querySelectorAll('.message-section').forEach(el => {
      el.classList.remove('layout-bubble', 'layout-default');
      el.classList.add(`layout-${normalized}`);
    });
  }

  setMessageSettings(json) {
    let s;
    try { s = typeof json === 'string' ? JSON.parse(json) : (json || {}); }
    catch (_) { s = {}; }
    this.batterySaver = !!s.batterySaver;
    this.disableSwipeRegeneration = !!s.disableSwipeRegeneration;
    const container = document.getElementById('chat-container') || document.body;
    container.classList.toggle('battery-saver', this.batterySaver);
    container.classList.toggle('hide-message-id', !!s.hideMessageId);
    container.classList.toggle('hide-gen-time', !!s.hideGenerationTime);
    container.classList.toggle('hide-token-count', !!s.hideTokenCount);
    // Battery saver kills the overlay backdrop-filter strips too.
    this._renderOverlayBlurRegions();
  }

  /* ---------- Inline edit (toggle into .msg-body) ---------- */
  startEdit(messageId) {
    this._editController.startEdit(messageId, (pos) => {
      if (pos !== undefined) this.virtualList.container.scrollTop = pos;
      return this.virtualList.container.scrollTop;
    });
    // After the textarea/footer have been swapped in (and the prior scroll
    // position restored by the controller), smoothly bring the top of the
    // edited message into view so the user starts editing from its beginning.
    this._scrollMessageToTop(messageId);
  }

  // Smoothly scroll so the top of [messageId] lands just below the translucent
  // header. The container carries a dynamic `padding-top` (header inset, see
  // setTopPadding), so we subtract it to avoid the message hiding behind it.
  _scrollMessageToTop(messageId) {
    const container = this.virtualList?.container;
    if (!container) return;
    requestAnimationFrame(() => {
      const section = document.querySelector(`[data-message-id="${messageId}"]`);
      if (!section || !container.isConnected) return;
      const cRect = container.getBoundingClientRect();
      const sRect = section.getBoundingClientRect();
      const padTop = parseFloat(getComputedStyle(container).paddingTop) || 0;
      const target = container.scrollTop + (sRect.top - cRect.top) - padTop - 8;
      this.virtualList.isProgrammaticScrolling = true;
      container.scrollTo({ top: Math.max(0, target), behavior: 'smooth' });
      setTimeout(() => {
        this.virtualList.isProgrammaticScrolling = false;
        // Re-sync the render window to the resting scroll position (scroll
        // events fired during the animation were gated out above).
        if (typeof this.virtualList.updateWindow === 'function') {
          this.virtualList.updateWindow();
        }
      }, 500);
    });
  }

  stopEdit(messageId) {
    this._editController.stopEdit(messageId);
  }

  setBackgroundImage(url, blur, opacity, dim) {
    // Duplicate the app background inside the WebView so its own
    // backdrop-filter blur regions have real pixels to sample — CSS
    // backdrop-filter can't see the natively-composited Flutter layer
    // behind the transparent WebView. Flutter keeps painting the same
    // background underneath as a fallback; this opaque copy sits on top.
    //
    // The bg blur must be BAKED into the image (offscreen canvas), not a
    // live `filter: blur()` on #bg-layer: a CSS filter turns the element
    // into a backdrop root (isolated composited layer), which excludes it
    // from every sibling backdrop-filter's sampling set — the overlay-blur
    // strips under the Flutter glass and the bubbles' element-blur would
    // silently go flat whenever bg blur is enabled.
    let bg = document.getElementById('bg-layer');
    const d = Math.max(0, Math.min(1, Number(dim) || 0));
    if (!url) {
      this._bgBlurToken = null;
      this._bgParams = null;
      if (bg) {
        bg.style.display = 'none';
        bg.style.backgroundImage = '';
      }
      // Wallpaper cleared: the grain (if any) rides its own layer again.
      this._renderStandaloneNoise();
      return;
    }
    // Remember the inputs so setBackgroundNoise can re-bake the grain into
    // #bg-layer without Flutter re-pushing the (possibly huge) data URI.
    this._bgParams = { url, blur, opacity, dim };
    if (!bg) {
      bg = document.createElement('div');
      bg.id = 'bg-layer';
      document.body.insertBefore(bg, document.body.firstChild);
    }
    bg.style.display = 'block';
    const op = opacity == null ? 1 : Math.max(0, Math.min(1, Number(opacity)));
    bg.style.opacity = op;

    const b = Math.max(0, Number(blur) || 0);
    const nOp = Math.max(0, Math.min(1, this._noiseOpacity || 0));
    const nInt = Math.max(
      0,
      Math.min(2, this._noiseIntensity == null ? 1 : this._noiseIntensity),
    );

    // Nothing to bake (no blur, no dim, no grain) → plain image.
    if (b <= 0 && d <= 0 && nOp <= 0) {
      this._bgBlurToken = null;
      bg.style.setProperty('--bg-dim', '0');
      bg.style.backgroundImage = `url("${url}")`;
      bg.style.filter = '';
      bg.style.inset = '0';
      this._renderStandaloneNoise();
      return;
    }

    // From here the grain is baked into #bg-layer, so the standalone grain layer
    // must stay hidden: it would otherwise double the noise, and its sub-1
    // opacity keeps it out of the glass's backdrop sampling anyway — which is
    // why the header / input blur went flat under heavy dimming, with nothing
    // textured left to sample once dim+blur flattened the wallpaper.
    const noiseLayer = document.getElementById('bg-noise-layer');
    if (noiseLayer) noiseLayer.style.display = 'none';

    const cacheKey = `${b}|${d}|${nOp}|${nInt}|${url}`;
    if (this._bgBlurCache && this._bgBlurCache.key === cacheKey) {
      this._bgBlurToken = null;
      this._applyBakedBg(bg, this._bgBlurCache.dataUrl);
      return;
    }

    // Immediate fallback while the canvas bake is in flight — and the permanent
    // fallback when canvas 2D filters are unsupported: live CSS blur plus the
    // ::after dim overlay (driven by an inline --bg-dim so it matches d exactly).
    // CSS blur on an inset:0 layer bleeds transparent (darkened) edges, unlike
    // Flutter's TileMode.clamp; overscan so the fringe falls outside the viewport.
    bg.style.setProperty('--bg-dim', String(d));
    bg.style.backgroundImage = `url("${url}")`;
    bg.style.filter = b > 0 ? `blur(${b}px)` : '';
    bg.style.inset = b > 0 ? `-${b * 2}px` : '0';

    const token = cacheKey;
    this._bgBlurToken = token;
    this._bakeBackground(url, b, d, nOp, nInt).then((dataUrl) => {
      if (!dataUrl) {
        // Canvas unsupported/failed: fall back to the standalone grain layer so
        // the wallpaper still carries some texture under the live-filter path.
        this._renderStandaloneNoise();
        return;
      }
      this._bgBlurCache = { key: cacheKey, dataUrl };
      if (this._bgBlurToken !== token) return; // superseded by a newer call
      const layer = document.getElementById('bg-layer');
      if (!layer || layer.style.display === 'none') return;
      this._applyBakedBg(layer, dataUrl);
    });
  }

  // Swap #bg-layer to the fully-baked image (blur + dim composited into the
  // pixels) with no live CSS filter, and switch the ::after dim overlay off
  // (inline --bg-dim:0). This keeps #bg-layer a plain painted layer — a CSS
  // `filter` or a semi-transparent dim overlay makes it a backdrop root that is
  // excluded from the header / input-bar backdrop-filter sampling, which is why
  // their glass blur went flat when a dimmed/blurred bg was set.
  // #bg-layer transitions `filter` 0.3s; suppress it for the swap so the baked
  // blur + decaying live blur don't visibly stack.
  _applyBakedBg(layer, dataUrl) {
    const prevTransition = layer.style.transition;
    layer.style.transition = 'none';
    layer.style.setProperty('--bg-dim', '0');
    layer.style.backgroundImage = `url("${dataUrl}")`;
    layer.style.filter = '';
    layer.style.inset = '0';
    void layer.offsetWidth; // flush so the un-transitioned state commits
    layer.style.transition = prevTransition;
  }

  // Renders [url] into an offscreen canvas with the blur AND the dim baked into
  // the pixels, once, at a capped working resolution. Resolves to a data URL, or
  // null when canvas 2D filters are unavailable (older WKWebView) or the render
  // fails — callers keep the live CSS-filter + ::after-dim fallback in that case.
  _bakeBackground(url, blur, dim, noiseOpacity, noiseIntensity) {
    return new Promise((resolve) => {
      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d');
      if (!ctx || typeof ctx.filter !== 'string') {
        resolve(null);
        return;
      }
      const img = new Image();
      // The wallpaper is served from the loopback file server, a different
      // origin than the chat page (file:// on Windows, app-assets on Android).
      // Request it as an anonymous CORS fetch (the file server answers with
      // Access-Control-Allow-Origin: *) so the canvas stays untainted and
      // toDataURL() below can read it back. Without this the bake throws on
      // cross-origin wallpapers and #bg-layer is stuck on the live-`filter`
      // fallback, which excludes it from the header / input-bar glass sampling
      // and flattens their blur. Harmless for same-origin and data: URLs.
      img.crossOrigin = 'anonymous';
      img.onload = () => {
        try {
          const iw = img.naturalWidth;
          const ih = img.naturalHeight;
          if (!iw || !ih) {
            resolve(null);
            return;
          }
          // The blur destroys detail anyway, so a capped resolution keeps
          // the canvas + data URL small; scale the radius to match.
          const scale = Math.min(1, 1536 / Math.max(iw, ih));
          canvas.width = Math.max(1, Math.round(iw * scale));
          canvas.height = Math.max(1, Math.round(ih * scale));
          if (blur > 0) {
            const scaledBlur = Math.max(0.5, blur * scale);
            // Overscan: draw expanded by 2×blur per side so the transparent
            // blurred fringe lands outside the canvas and edges stay clamped
            // (Flutter TileMode.clamp equivalent), at the cost of a slight
            // zoom-crop.
            const pad = Math.ceil(scaledBlur * 2);
            ctx.filter = `blur(${scaledBlur}px)`;
            ctx.drawImage(
              img,
              -pad,
              -pad,
              canvas.width + pad * 2,
              canvas.height + pad * 2,
            );
            ctx.filter = 'none';
          } else {
            ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
          }
          // Bake the dim on top so #bg-layer needs no live dim overlay.
          if (dim > 0) {
            ctx.fillStyle = `rgba(0, 0, 0, ${dim})`;
            ctx.fillRect(0, 0, canvas.width, canvas.height);
          }
          // Bake the grain over the dim so the sampled backdrop keeps
          // high-frequency detail the header / input-bar glass can blur — even
          // when heavy dimming would otherwise flatten it to a solid color and
          // leave the glass nothing to frost.
          if (noiseOpacity > 0) {
            const pattern = ctx.createPattern(
              this._noiseCanvas(noiseIntensity),
              'repeat',
            );
            if (pattern) {
              ctx.globalAlpha = noiseOpacity;
              ctx.fillStyle = pattern;
              ctx.fillRect(0, 0, canvas.width, canvas.height);
              ctx.globalAlpha = 1;
            }
          }
          // WebP keeps the alpha channel (PNG wallpapers) unlike JPEG;
          // engines without a WebP encoder silently return PNG instead.
          resolve(canvas.toDataURL('image/webp', 0.9));
        } catch (_) {
          resolve(null);
        }
      };
      img.onerror = () => resolve(null);
      img.src = url;
    });
  }

  setBackgroundNoise(opacity, intensity) {
    this._noiseOpacity = Math.max(0, Math.min(1, opacity || 0));
    this._noiseIntensity = Math.max(
      0,
      Math.min(2, intensity == null ? 1 : intensity),
    );

    // With a wallpaper active the grain is baked straight into #bg-layer (see
    // setBackgroundImage) so the header / input-bar glass can sample it. Re-bake
    // with the new grain and keep the standalone layer hidden to avoid doubling.
    if (this._bgParams && this._bgParams.url) {
      const existing = document.getElementById('bg-noise-layer');
      if (existing) existing.style.display = 'none';
      const p = this._bgParams;
      this.setBackgroundImage(p.url, p.blur, p.opacity, p.dim);
      return;
    }

    // No wallpaper → the grain rides on its own fixed layer over the flat color
    // background.
    this._renderStandaloneNoise();
  }

  // Build / update / hide the standalone #bg-noise-layer from the stored grain
  // settings. Used when there is no wallpaper to bake the grain into, and as the
  // fallback when the canvas bake is unavailable.
  _renderStandaloneNoise() {
    let noise = document.getElementById('bg-noise-layer');
    const op = Math.max(0, Math.min(1, this._noiseOpacity || 0));
    if (op <= 0) {
      if (noise) {
        noise.style.display = 'none';
        noise.style.backgroundImage = '';
      }
      return;
    }
    if (!noise) {
      noise = document.createElement('div');
      noise.id = 'bg-noise-layer';
      const bg = document.getElementById('bg-layer');
      if (bg && bg.nextSibling) {
        document.body.insertBefore(noise, bg.nextSibling);
      } else {
        document.body.insertBefore(noise, document.body.firstChild);
      }
    }
    const i = Math.max(
      0,
      Math.min(2, this._noiseIntensity == null ? 1 : this._noiseIntensity),
    );
    noise.style.display = 'block';
    noise.style.opacity = op;
    noise.style.backgroundImage = `url("${this._noiseTile(i)}")`;
    noise.style.backgroundSize = '128px 128px';
  }

  _noiseTile(intensity) {
    if (!this._noiseCache) this._noiseCache = new Map();
    const key = intensity.toFixed(2);
    const hit = this._noiseCache.get(key);
    if (hit) return hit;
    const url = this._noiseCanvas(intensity).toDataURL('image/png');
    this._noiseCache.set(key, url);
    return url;
  }

  // 128×128 grain tile as an offscreen canvas (cached by intensity). Reused both
  // as a repeating CSS background (via toDataURL in _noiseTile) and as a canvas
  // pattern baked straight into the wallpaper in _bakeBackground, so both grain
  // paths share one stable tile.
  _noiseCanvas(intensity) {
    if (!this._noiseCanvasCache) this._noiseCanvasCache = new Map();
    const key = intensity.toFixed(2);
    const hit = this._noiseCanvasCache.get(key);
    if (hit) return hit;
    const size = 128;
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = size;
    const ctx = canvas.getContext('2d');
    const img = ctx.createImageData(size, size);
    const data = img.data;
    for (let p = 0; p < data.length; p += 4) {
      const a = Math.min(1, Math.random() * intensity);
      data[p] = 255;
      data[p + 1] = 255;
      data[p + 2] = 255;
      data[p + 3] = Math.round(a * 255);
    }
    ctx.putImageData(img, 0, 0);
    this._noiseCanvasCache.set(key, canvas);
    return canvas;
  }

  setPerformanceMode(enabled) {
    const container = document.getElementById('chat-container') || document.body;
    container.classList.toggle('perf-mode', !!enabled);
    /* Mirror .native-lite onto each message for class-scoped styles */
    document.querySelectorAll('.message-section').forEach(el => {
      el.classList.toggle('native-lite', !!enabled);
    });
  }

  animateGenTime(messageId, targetTime) {
    const section = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!section) return;
    const badge = section.querySelector('.gen-time-badge');
    if (!badge) return;

    const match = targetTime.match(/([\d.]+)(.*)/);
    if (!match) { badge.textContent = targetTime; return; }
    const target = parseFloat(match[1]);
    const suffix = match[2] || '';
    if (isNaN(target)) { badge.textContent = targetTime; return; }

    const start = performance.now();
    const duration = 600;
    const tick = (now) => {
      const progress = Math.min((now - start) / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = (target * eased).toFixed(target % 1 !== 0 ? 1 : 0);
      badge.textContent = `${current}${suffix}`;
      if (progress < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  setSelectionMode(enabled) { this._selectionManager.setSelectionMode(enabled); }

  _setupImageClickForward() {
    this.virtualList.container.addEventListener('image-click', (e) => {
      this._sendToFlutter('onImageClick', [e.detail.src]);
    });
  }

  debugFormatter(text) {
    const formatted = this.renderer.formatter.format(text, false);
    document.title = 'DBG:' + formatted.substring(0, 200);
  }

  // ── Interactive panels (sandboxed iframe islands) ──────────────────────

  /**
   * Persistent, sandboxed iframe islands rendered under assistant messages.
   * Unlike `runSandboxedScript`, these stay alive for the entire lifetime
   * of the message so the user can interact with the panel (click, type,
   * fetch via glaze.* etc.) and call back into Dart through the standard
   * `glaze:request` postMessage relay.
   *
   * Security model:
   *   - iframe uses `sandbox="allow-scripts"` WITHOUT `allow-same-origin`
   *     → null origin blocks `window.parent` and `window.flutter_inappwebview`
   *   - All `glaze.*` calls go through the same parent reлай as
   *     `runSandboxedScript`, so cross-origin spoofing is impossible:
   *     parent only answers if `e.source === iframe.contentWindow`
   *   - Iframe HTML is constructed in two parts: a trusted SDK bootstrap
   *     (`window.__glazeSdkSource`) + caller-supplied HTML in a sandbox
   *     container. The user HTML is **not** injected via `innerHTML` on the
   *     parent side — only the iframe sees it.
   *   - ResizeObserver reports height back to Dart so the virtual list
   *     can keep the cached section height in sync.
   */
  initPanelHost() {
    if (this._panelHost) return;
    this._panelHost = new PanelHost(this);
  }

  openPanel(messageId, html, optionsJson) {
    this.initPanelHost();
    return this._panelHost.open(messageId, html, optionsJson || '{}');
  }

  closePanel(panelId) {
    this._panelHost?.close(panelId);
  }

  postToPanel(panelId, method, paramsJson) {
    return this._panelHost?.postToPanel(panelId, method, paramsJson || '{}');
  }

  // ── Ext Blocks panel ──────────────────────────────────────────────────────

  /**
   * Called from Flutter to show/update the inline ext-blocks panel under a
   * message. If `blocks` is empty the panel is removed.
   * @param {string} json  - JSON string: { messageId: string, blocks: Array }
   */
  showExtBlocksPanel(json) {
    let data;
    try { data = JSON.parse(json); } catch (_) { return; }
    const { messageId, blocks, canRunAll } = data;
    if (!messageId) return;

    const section = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!section) return;

    if (!blocks || blocks.length === 0) {
      section.querySelector('.ext-blocks-panel')?.remove();
      return;
    }

    let panel = section.querySelector('.ext-blocks-panel');
    if (!panel) {
      panel = document.createElement('div');
      panel.className = 'ext-blocks-panel';
      const content = section.querySelector('.msg-content') || section;
      content.appendChild(panel);
    }

    panel.innerHTML = '';

    if (canRunAll) {
      const toolbar = document.createElement('div');
      toolbar.className = 'ext-blocks-toolbar';
      const runAllBtn = document.createElement('button');
      runAllBtn.type = 'button';
      runAllBtn.className = 'ext-block-btn ext-blocks-run-all';
      runAllBtn.dataset.action = 'ext-blocks-run-all';
      runAllBtn.dataset.messageId = messageId;
      runAllBtn.textContent = '▶ Запустить блоки';
      toolbar.appendChild(runAllBtn);
      panel.appendChild(toolbar);
    }

    for (const block of blocks) {
      const item = document.createElement('div');
      item.className = `ext-block-item ${block.status || 'done'}`;
      item.dataset.blockId = block.blockId;

      const header = document.createElement('div');
      header.className = 'ext-block-header';

      const caret = document.createElement('span');
      caret.className = 'ext-block-caret';
      caret.textContent = '▸';
      header.appendChild(caret);

      const name = document.createElement('span');
      name.className = 'ext-block-name';
      name.textContent = block.blockName || block.blockId || '—';
      header.appendChild(name);

      const statusEl = document.createElement('span');
      statusEl.className = 'ext-block-status';
      statusEl.textContent = this._extBlockStatusLabel(block.status);
      header.appendChild(statusEl);

      // Buttons — no per-btnGroup listener so the click bubbles up to the
      // document-level delegation in `_interaction.handleClick` (which
      // dispatches via `_actionMap`). The header's own click listener has
      // a `closest('.ext-block-btn')` guard so it won't toggle collapse.
      const btnGroup = document.createElement('span');
      btnGroup.className = 'ext-block-actions';

      // Edit button — always present.
      const editBtn = document.createElement('button');
      editBtn.type = 'button';
      editBtn.className = 'ext-block-btn ext-block-btn-icon';
      editBtn.dataset.action = 'ext-block-edit';
      editBtn.dataset.blockId = block.blockId;
      editBtn.dataset.messageId = messageId;
      editBtn.title = 'Редактировать';
      editBtn.textContent = '✎';
      btnGroup.appendChild(editBtn);

      // Delete button — always present.
      const deleteBtn = document.createElement('button');
      deleteBtn.type = 'button';
      deleteBtn.className = 'ext-block-btn ext-block-btn-icon ext-block-btn-danger';
      deleteBtn.dataset.action = 'ext-block-delete';
      deleteBtn.dataset.blockId = block.blockId;
      deleteBtn.dataset.messageId = messageId;
      deleteBtn.title = 'Удалить';
      deleteBtn.textContent = '✕';
      btnGroup.appendChild(deleteBtn);

      if (block.status === 'running') {
        const stopBtn = document.createElement('button');
        stopBtn.type = 'button';
        stopBtn.className = 'ext-block-btn';
        stopBtn.dataset.action = 'ext-block-stop';
        stopBtn.dataset.blockId = block.blockId;
        stopBtn.dataset.messageId = messageId;
        stopBtn.textContent = '■ Стоп';
        btnGroup.appendChild(stopBtn);
      } else if (block.status === 'pending') {
        const startBtn = document.createElement('button');
        startBtn.type = 'button';
        startBtn.className = 'ext-block-btn';
        startBtn.dataset.action = 'ext-block-regen';
        startBtn.dataset.blockId = block.blockId;
        startBtn.dataset.messageId = messageId;
        startBtn.textContent = '▶ Запустить';
        btnGroup.appendChild(startBtn);
      } else {
        const canRegenImage = block.type === 'imageGen' && block.content && (
          /\[IMG:RESULT:/.test(block.content) ||
          /\[IMG:GEN:/.test(block.content) ||
          /data-iig-instruction/i.test(block.content)
        );
        if (canRegenImage) {
          const imgRegenBtn = document.createElement('button');
          imgRegenBtn.type = 'button';
          imgRegenBtn.className = 'ext-block-btn';
          imgRegenBtn.dataset.action = 'ext-block-regen-image';
          imgRegenBtn.dataset.blockId = block.blockId;
          imgRegenBtn.dataset.messageId = messageId;
          imgRegenBtn.textContent = '↺ Картинка';
          btnGroup.appendChild(imgRegenBtn);
        }
        const regenBtn = document.createElement('button');
        regenBtn.type = 'button';
        regenBtn.className = 'ext-block-btn';
        regenBtn.dataset.action = 'ext-block-regen';
        regenBtn.dataset.blockId = block.blockId;
        regenBtn.dataset.messageId = messageId;
        regenBtn.textContent = '↺ Перегенерировать';
        btnGroup.appendChild(regenBtn);
      }

      header.appendChild(btnGroup);
      header.addEventListener('click', (e) => {
        if (e.target.closest('.ext-block-btn')) return;
        item.classList.toggle('collapsed');
      });
      item.appendChild(header);

      // Content body (collapsible).
      const body = document.createElement('div');
      body.className = 'ext-block-body';
      this._fillExtBlockBody(body, block);
      item.appendChild(body);

      panel.appendChild(item);
    }
  }

  /**
   * Lightweight streaming update — only replaces one block's body + status.
   * Returns false if the panel or block row is not on screen yet.
   */
  patchExtBlockContent(json) {
    let data;
    try { data = JSON.parse(json); } catch (_) { return false; }
    const { messageId, blockId, content, status } = data;
    if (!messageId || !blockId) return false;

    const section = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!section) return false;
    const panel = section.querySelector('.ext-blocks-panel');
    if (!panel) return false;

    const item = panel.querySelector(`.ext-block-item[data-block-id="${blockId}"]`);
    if (!item) return false;

    item.className = `ext-block-item ${status || 'running'}`;
    const statusEl = item.querySelector('.ext-block-status');
    if (statusEl) statusEl.textContent = this._extBlockStatusLabel(status);

    const body = item.querySelector('.ext-block-body');
    if (!body) return false;
    body.innerHTML = '';
    this._fillExtBlockBody(body, { content, status });
    item.classList.remove('collapsed');
    return true;
  }

  _escapeAttr(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  _extBlockImageSrc(payload) {
    let path = payload || '';
    const pipeIdx = path.indexOf('|');
    if (pipeIdx !== -1) path = path.substring(0, pipeIdx);
    if (path.startsWith('data:') || path.startsWith('file://') || path.startsWith('http://') || path.startsWith('https://')) return path;
    const normalized = path.replace(/\\/g, '/');
    return normalized.startsWith('/') ? `file://${normalized}` : `file:///${normalized}`;
  }

  _renderExtBlockImageHtml(payload) {
    const src = this._escapeAttr(this._extBlockImageSrc(payload));
    return `<span class="ext-block-image-wrapper img-result-wrapper"><img src="${src}" class="ext-block-image" loading="lazy" data-action="image-click" data-src="${src}"><button class="img-download-btn" data-action="img-download" data-src="${src}" title="Save image">⤓</button></span>`;
  }

  _fillExtBlockBody(body, block) {
    const hasContent = block.content && block.content.trim().length > 0;
    if (!hasContent && block.status !== 'pending') {
      const empty = document.createElement('div');
      empty.className = 'ext-block-content empty';
      empty.textContent = '(пусто)';
      body.appendChild(empty);
      return;
    }
    if (!hasContent) return;

    const imgResultRegex = /\[IMG:RESULT:([^\]]+)\]/;
    const hasImgResult = imgResultRegex.test(block.content);
    const hasHtmlMarkup = /<[a-z][\s\S]*>/i.test(block.content);

    if (hasImgResult && hasHtmlMarkup) {
      let html = block.content.replace(
        /\[IMG:RESULT:([^\]]+)\]/g,
        (match, payload) => this._renderExtBlockImageHtml(payload),
      );
      const htmlEl = document.createElement('div');
      htmlEl.className = 'ext-block-content';
      htmlEl.innerHTML = html;
      body.appendChild(htmlEl);
    } else if (hasImgResult) {
      const imgMatch = block.content.match(imgResultRegex);
      const wrapper = document.createElement('span');
      wrapper.innerHTML = this._renderExtBlockImageHtml(imgMatch[1]);
      body.appendChild(wrapper.firstElementChild);
    } else {
      const html = document.createElement('div');
      html.className = 'ext-block-content';
      html.innerHTML = block.content;
      body.appendChild(html);
    }
  }

  /**
   * Updates the panel if it's currently visible for this message.
   * Has the same signature as showExtBlocksPanel — just delegates.
   */
  updateExtBlocksPanel(json) {
    this.showExtBlocksPanel(json);
  }

  hideExtBlocksPanel(messageId) {
    if (!messageId) return;
    const section = document.querySelector(`[data-message-id="${messageId}"]`);
    section?.querySelector('.ext-blocks-panel')?.remove();
  }

  _extBlockStatusLabel(status) {
    switch (status) {
      case 'pending': return 'ожидает';
      case 'running': return 'генерация…';
      case 'error': return 'ошибка';
      case 'stopped': return 'остановлен';
      case 'done': return 'готово';
      default: return status || '—';
    }
  }

  /**
   * Called from Flutter to push a minimal updateMessageMeta call.
   * `json` is the same shape as a message object (at least { id, blockStatus }).
   */
  updateMessageMeta(json) {
    let msg;
    try { msg = JSON.parse(json); } catch (_) { return; }
    if (!msg.id) return;
    const section = document.querySelector(`[data-message-id="${msg.id}"]`);
    if (!section) return;
    this.renderer.updateMessageMeta(section, msg);
  }

  /**
   * Runs user-provided JS in a sandboxed iframe and returns a Promise<string>.
   *
   * Security model:
   *   - iframe uses sandbox="allow-scripts" WITHOUT allow-same-origin
   *   - This gives the iframe a null origin, blocking access to window.parent
   *     and window.flutter_inappwebview (cross-origin barrier)
   *   - Context is passed via srcdoc (not postMessage) to avoid the timing
   *     issue of the iframe not being ready yet
   *   - Only text data is passed: messages, character fields, previousOutput
   *   - API keys are never in JS context (they live in Dart/SQLite)
   *   - Source-check: e.source !== iframe.contentWindow guards against spoofing
   *   - Timeout: 55 s (Dart side gives 60 s — races without leaking)
   *
   * @param {string} script - User JS. Must return a string (via `return`).
   * @param {string} contextJson - JSON string with messages/character/previousOutput.
   * @returns {Promise<string>}
   */
  runSandboxedScript(script, contextJson) {
    return new Promise((resolve, reject) => {
      let iframe = null;

      const cleanup = () => {
        if (iframe) {
          iframe.remove();
          iframe = null;
        }
      };

      const timeoutId = setTimeout(() => {
        cleanup();
        reject(new Error('JS runner timeout (55s)'));
      }, 55000);

      // Escape script and contextJson for safe embedding in srcdoc attribute.
      // We use a JSON string as the JS literal so that any quotes/backslashes
      // inside the user script are properly escaped.
      const escapedScript = JSON.stringify(script);
      const escapedContext = contextJson;
      const sdkSource = JSON.stringify(window.__glazeSdkSource || '');

      const sandboxHtml = `<!DOCTYPE html><html><body><script>
(function() {
  var context;
  try { context = ${escapedContext}; } catch(e) { context = {}; }
  window.__glazeContext = context;
  var glazeSdkSource = ${sdkSource};
  if (glazeSdkSource) {
    (new Function(glazeSdkSource))();
  }
  var userScript = ${escapedScript};
  (new Function('context', '"use strict"; return (async function() { ' + userScript + ' })();'))(context)
    .then(function(r) {
      parent.postMessage({ ok: true, result: String(r !== undefined && r !== null ? r : '') }, '*');
    })
    .catch(function(e) {
      parent.postMessage({ ok: false, error: String(e && e.message ? e.message : e) }, '*');
    });
})();
<\/script></body></html>`;

      const handler = (e) => {
        if (!iframe || e.source !== iframe.contentWindow) return;
        if (e.data && e.data.type) return;
        clearTimeout(timeoutId);
        window.removeEventListener('message', handler);
        cleanup();
        if (e.data && e.data.ok) {
          resolve(e.data.result);
        } else {
          reject(new Error(e.data && e.data.error ? e.data.error : 'JS runner error'));
        }
      };

      window.addEventListener('message', handler);

      iframe = document.createElement('iframe');
      iframe.sandbox = 'allow-scripts';
      iframe.style.display = 'none';
      iframe.srcdoc = sandboxHtml;
      document.body.appendChild(iframe);
    });
  }
}
