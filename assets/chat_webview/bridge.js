/* ============================================================
 * Bridge — communication with Flutter side.
 * Selectors follow ChatMessage.vue's class naming (.message-section, .msg-*).
 * Flutter callHandler contract is preserved — useMessageActions lives in Dart.
 * ============================================================ */

class Bridge {
  constructor(renderer, virtualList) {
    this.renderer = renderer;
    this.virtualList = virtualList;
    this._pendingRequests = new Map();
    this._requestCounter = 0;
    this.isGenerating = false;
    this.isGeneratingImage = false;
    this._setupScrollListener();
    this._setupInteractionListener();
    this._setupImageClickForward();
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
    let lastScrollTop = 0;
    this.virtualList.container.addEventListener('scroll', () => {
      if (loadMoreCooldown || this._suppressLoadMore) return;
      const st = this.virtualList.container.scrollTop;
      const scrollingUp = st < lastScrollTop;
      lastScrollTop = st;
      if (!scrollingUp) return;
      if (this.virtualList.isNearTop(500)) {
        loadMoreCooldown = true;
        this._sendToFlutter('onLoadMore', []);
        setTimeout(() => { loadMoreCooldown = false; }, 500);
      }
    });
  }

  /* ---------- Interaction dispatch ---------- */
  _setupInteractionListener() {
    document.addEventListener('click', (e) => {
      /* Selection checkbox */
      if (e.target.closest('.selection-checkbox')) {
        this._handleSelectionCheckbox(e);
        return;
      }

      /* Reasoning collapse */
      const reasoningHdr = e.target.closest('[data-action="toggle-reasoning"]');
      if (reasoningHdr) {
        const block = reasoningHdr.closest('.msg-reasoning');
        if (block) block.classList.toggle('collapsed');
        return;
      }

      /* External links */
      const link = e.target.closest('a');
      if (link) {
        e.preventDefault();
        this._sendToFlutter('onLinkClick', [link.href]);
        return;
      }

      /* Memory badge → Flutter */
      const memoryBadge = e.target.closest('[data-action="memory-click"]');
      if (memoryBadge) {
        this._sendToFlutter('onMemoryClick', [memoryBadge.dataset.messageId]);
        return;
      }

      /* Triggered items / inject menu */
      const injectBadge = e.target.closest('[data-action="inject-click"]');
      if (injectBadge) {
        this._sendToFlutter('onInjectClick', [injectBadge.dataset.messageId]);
        return;
      }

      /* Hidden eye toggle */
      const hiddenToggle = e.target.closest('[data-action="toggle-hidden"]');
      if (hiddenToggle) {
        this._sendToFlutter('onToggleHidden', [hiddenToggle.dataset.messageId]);
        return;
      }

      /* Image-context-hidden toggle */
      const imgHiddenToggle = e.target.closest('[data-action="toggle-image-hidden"]');
      if (imgHiddenToggle) {
        const section = imgHiddenToggle.closest('.message-section');
        const id = section ? section.dataset.messageId : '';
        this._sendToFlutter('onToggleImageHidden', [id]);
        return;
      }

      /* Swipe nav (assistant variants) */
      const swipeBtn = e.target.closest('[data-action="swipe-left"], [data-action="swipe-right"]');
      if (swipeBtn) {
        const action = swipeBtn.dataset.action;
        const id = swipeBtn.dataset.messageId;
        this._sendToFlutter('onSwipe', [JSON.stringify({
          id, direction: action === 'swipe-right' ? 'right' : 'left'
        })]);
        return;
      }

      /* Greeting nav (first message) */
      const greetingBtn = e.target.closest('[data-action="greeting-prev"], [data-action="greeting-next"]');
      if (greetingBtn) {
        const dir = greetingBtn.dataset.action === 'greeting-next' ? 1 : -1;
        this._sendToFlutter('onChangeGreeting', [greetingBtn.dataset.messageId, dir]);
        return;
      }

      /* Stop generation */
      const stopBtn = e.target.closest('[data-action="stop"], .stop-btn');
      if (stopBtn) {
        this._sendToFlutter('onStop', []);
        return;
      }

      /* Regenerate (last user / error) */
      const regenBtn = e.target.closest('[data-action="regenerate"], .msg-regenerate');
      if (regenBtn) {
        const id = regenBtn.dataset.messageId;
        const mode = regenBtn.dataset.mode || 'magic';
        this._sendToFlutter('onRegenerate', [id, mode]);
        return;
      }

      /* Guided swipe toggle */
      const guidedBtn = e.target.closest('[data-action="toggle-guided"], .msg-guided-swipe-btn');
      if (guidedBtn) {
        this._toggleGuidedSwipe(guidedBtn.dataset.messageId);
        return;
      }

      /* Edit save / cancel */
      const editSave = e.target.closest('[data-action="edit-save"]');
      if (editSave) {
        const section = editSave.closest('.message-section');
        const ta = section ? section.querySelector('.edit-textarea') : null;
        const id = editSave.dataset.messageId;
        const text = ta ? ta.value : '';
        this._sendToFlutter('onEditSave', [id, text]);
        return;
      }
      const editCancel = e.target.closest('[data-action="edit-cancel"]');
      if (editCancel) {
        this._sendToFlutter('onEditCancel', [editCancel.dataset.messageId]);
        return;
      }

      /* Actions menu (kebab) */
      const actionsBtn = e.target.closest('[data-action="open-actions"], .msg-actions-btn');
      if (actionsBtn) {
        const id = actionsBtn.dataset.messageId;
        const section = document.querySelector(`[data-message-id="${id}"]`);
        if (section) {
          const isUser = section.classList.contains('user');
          const isSystem = section.classList.contains('system');
          const content = this._extractText(section);
          this._sendToFlutter('onMessageContext', [JSON.stringify({ id, isUser, isSystem, content })]);
        }
        return;
      }

      /* Image gen frames */
      const path = e.composedPath();

      const imgRetryBtn = path.find(el => el.matches?.('[data-action="img-retry"]'));
      if (imgRetryBtn) {
        const sec = path.find(el => el.dataset?.messageId);
        const messageId = sec ? sec.dataset.messageId : '';
        let instr = '';
        try { instr = decodeURIComponent(imgRetryBtn.dataset.instruction || ''); }
        catch (_) { instr = imgRetryBtn.dataset.instruction || ''; }
        this._sendToFlutter('onImgRetry', [instr, messageId]);
        return;
      }
      const imgFindBtn = path.find(el => el.matches?.('[data-action="img-find"]'));
      if (imgFindBtn) {
        const sec = path.find(el => el.dataset?.messageId);
        const messageId = sec ? sec.dataset.messageId : '';
        let instr = '';
        try { instr = decodeURIComponent(imgFindBtn.dataset.instruction || ''); }
        catch (_) { instr = imgFindBtn.dataset.instruction || ''; }
        this._sendToFlutter('onImgFind', [instr, messageId]);
        return;
      }
      const imgRegenBtn = path.find(el => el.matches?.('[data-action="img-regen"]'));
      if (imgRegenBtn) {
        const sec = path.find(el => el.dataset?.messageId);
        const messageId = sec ? sec.dataset.messageId : '';
        let instr = '';
        try { instr = decodeURIComponent(imgRegenBtn.dataset.instruction || ''); }
        catch (_) { instr = imgRegenBtn.dataset.instruction || ''; }
        this._sendToFlutter('onImgRegen', [instr, messageId]);
        return;
      }
      const imgStopBtn = path.find(el => el.matches?.('[data-action="img-stop"]'));
      if (imgStopBtn) {
        this._sendToFlutter('onImgCancel', []);
        return;
      }

      /* Error copy */
      const errorCopyBtn = e.target.closest('.error-copy-btn');
      if (errorCopyBtn) {
        const id = errorCopyBtn.dataset.messageId;
        const section = document.querySelector(`[data-message-id="${id}"]`);
        if (section) {
          const raw = section.dataset.rawText || '';
          try { navigator.clipboard.writeText(raw); }
          catch (_) {
            const ta = document.createElement('textarea');
            ta.value = raw;
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            ta.remove();
          }
          errorCopyBtn.dataset.copied = '1';
          setTimeout(() => { delete errorCopyBtn.dataset.copied; }, 1200);
        }
        return;
      }

      /* Avatar tap */
      const avatar = e.target.closest('.msg-avatar');
      if (avatar) {
        const section = avatar.closest('.message-section');
        if (section) this._sendToFlutter('onAvatarClick', [section.dataset.messageId]);
        return;
      }

      /* Image tap (inside body) */
      const img = e.target.closest('.msg-image-attachment img');
      if (img && img.src) {
        this._sendToFlutter('onImageClick', [img.src]);
        return;
      }

      this._hideSelectionBar();
    });

    /* Selection bar */
    document.addEventListener('selectionchange', () => {
      let selText = '';
      const sel = window.getSelection();
      if (sel && sel.toString().trim().length > 0) {
        selText = sel.toString().trim();
      }
      if (!selText) {
        const hosts = document.querySelectorAll('.message-content');
        for (const el of hosts) {
          if (el.shadowRoot) {
            const shadowSel = el.shadowRoot.getSelection ? el.shadowRoot.getSelection() : null;
            if (shadowSel && shadowSel.toString().trim().length > 0) {
              selText = shadowSel.toString().trim();
              break;
            }
          }
        }
      }
      if (selText) this._showSelectionBar(selText);
      else this._hideSelectionBar();
    });

    /* Right-click → actions menu */
    document.addEventListener('contextmenu', (e) => {
      const section = e.target.closest('.message-section');
      if (!section) return;
      e.preventDefault();
      const id = section.dataset.messageId;
      const isUser = section.classList.contains('user');
      const isSystem = section.classList.contains('system');
      const content = this._extractText(section);
      this._sendToFlutter('onMessageContext', [JSON.stringify({ id, isUser, isSystem, content })]);
    });
  }

  _extractText(section) {
    const host = section.querySelector('.msg-body .message-content');
    if (host && host.shadowRoot) {
      const root = host.shadowRoot.querySelector('.glaze-message');
      if (root) return root.textContent || '';
    }
    return section.dataset.rawText || '';
  }

  /* ---------- Selection bar ---------- */
  _showSelectionBar(text) {
    let bar = document.getElementById('selection-bar');
    if (!bar) {
      bar = document.createElement('div');
      bar.id = 'selection-bar';
      bar.className = 'selection-bar';
      bar.innerHTML = '<button class="sel-btn" data-action="copy">Copy</button><button class="sel-btn" data-action="quote">Quote</button>';
      bar.addEventListener('click', (e) => {
        const btn = e.target.closest('.sel-btn');
        if (!btn) return;
        const action = btn.dataset.action;
        this._sendToFlutter('onSelectionAction', [JSON.stringify({ action, text: this._selectedText })]);
        this._hideSelectionBar();
        window.getSelection().removeAllRanges();
      });
      document.body.appendChild(bar);
    }
    this._selectedText = text;
    bar.style.display = 'flex';
  }

  _hideSelectionBar() {
    const bar = document.getElementById('selection-bar');
    if (bar) bar.style.display = 'none';
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
  setMessages(messagesJson) {
    this._suppressLoadMore = true;
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
      if (Array.isArray(rendered)) {
        for (const el of rendered) {
          const id = el.dataset.messageId || `__date_${el.dataset.dateSeparator || Date.now()}`;
          ids.push(id);
          elements.push(el);
        }
      } else {
        ids.push(msg.id);
        elements.push(rendered);
      }
    }

    this.virtualList.setMessagesBatch(ids, elements);
    this._hideLoadingScreen();
    setTimeout(() => { this._suppressLoadMore = false; }, 1000);
  }

  appendMessage(messageJson) {
    const msg = JSON.parse(messageJson);
    const rendered = this.renderer.renderMessage(msg);
    if (Array.isArray(rendered)) {
      for (const el of rendered) {
        const id = el.dataset.messageId || `__date_${el.dataset.dateSeparator || Date.now()}`;
        this.virtualList.append(id, el);
      }
    } else {
      this.virtualList.append(msg.id, rendered);
    }
    this.virtualList.scrollToBottom();
  }

  appendMessages(messagesJson) {
    const messages = JSON.parse(messagesJson);
    messages.forEach(msg => {
      const rendered = this.renderer.renderMessage(msg);
      if (Array.isArray(rendered)) {
        for (const el of rendered) {
          const id = el.dataset.messageId || `__date_${el.dataset.dateSeparator || Date.now()}`;
          this.virtualList.append(id, el);
        }
      } else {
        this.virtualList.append(msg.id, rendered);
      }
    });
  }

  prependMessages(messagesJson) {
    this._suppressLoadMore = true;
    const messages = JSON.parse(messagesJson);
    const scrollBefore = this.virtualList.container.scrollHeight;
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i];
      const rendered = this.renderer.renderMessage(msg);
      if (Array.isArray(rendered)) {
        for (let j = rendered.length - 1; j >= 0; j--) {
          const el = rendered[j];
          const id = el.dataset.messageId || `__date_${el.dataset.dateSeparator || Date.now()}`;
          this.virtualList.prepend(id, el);
        }
      } else {
        this.virtualList.prepend(msg.id, rendered);
      }
    }
    const scrollAfter = this.virtualList.container.scrollHeight;
    this.virtualList.container.scrollTop += scrollAfter - scrollBefore;
    this._hideLoadingScreen();
    setTimeout(() => { this._suppressLoadMore = false; }, 500);
  }

  updateMessage(messageJson) {
    const msg = JSON.parse(messageJson);
    const section = document.querySelector(`[data-message-id="${msg.id}"]`);
    if (!section) return;

    const animate = !!msg.swipeDirection;
    if (msg.swipeDirection) section.dataset.swipeDirection = msg.swipeDirection;

    if (msg.reasoning) section.dataset.reasoning = msg.reasoning;
    else if (msg.reasoning === null || msg.reasoning === '') delete section.dataset.reasoning;

    if (msg.text != null) section.dataset.rawText = msg.text;

    const isUser = section.classList.contains('user');
    this.renderer.updateMessageContent(
      section,
      msg.text != null ? msg.text : (section.dataset.rawText || ''),
      msg.reasoning ?? null,
      isUser,
      !!msg.isTyping,
      animate
    );

    if (msg.isHidden !== undefined) {
      section.classList.toggle('msg-hidden', !!msg.isHidden);
    }

    if (msg.swipeTotal !== undefined && msg.swipeTotal > 1) {
      const switcher = section.querySelector('.msg-switcher .msg-switcher-count');
      if (switcher) switcher.textContent = `${(msg.swipeIndex || 0) + 1}/${msg.swipeTotal}`;
    }

    this.renderer.updateMessageMeta(section, msg);
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

  removeMessage(messageId) { this.virtualList.remove(messageId); }

  clearAll() {
    this._showLoadingScreen();
    this.virtualList.clear();
  }

  scrollToBottom() { this.virtualList.scrollToBottom(); }
  scrollToMessage(messageId) { this.virtualList.scrollToMessage(messageId); }

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

  applyTheme(themeJson) {
    const theme = JSON.parse(themeJson);
    const container = document.getElementById('chat-container') || document.body;

    for (const [key, value] of Object.entries(theme)) {
      if (key === 'chat-layout') {
        container.classList.remove('layout-bubble', 'layout-default');
        container.classList.add(`layout-${value || 'default'}`);
        continue;
      }
      document.documentElement.style.setProperty(`--${key}`, value);
    }
  }

  setBottomPadding(px) {
    const container = document.getElementById('chat-container') || document.body;
    container.style.paddingBottom = px + 'px';
  }

  setTopPadding(px) {
    const container = document.getElementById('chat-container') || document.body;
    container.style.paddingTop = px + 'px';
  }

  applyLayout(layout) {
    const container = document.getElementById('chat-container') || document.body;
    container.classList.remove('layout-bubble', 'layout-default');
    container.classList.add(`layout-${layout || 'default'}`);
  }

  /* ---------- Inline edit (toggle into .msg-body) ---------- */
  startEdit(messageId) {
    const section = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!section) return;

    const scrollPos = this.virtualList.container.scrollTop;
    section.classList.add('editing');

    const rawText = section.dataset.rawText || '';
    const reasoning = section.dataset.reasoning || '';
    let editText = rawText;
    if (reasoning) editText = '<' + 'think>\n' + reasoning + '\n</' + 'think>\n' + rawText;

    const body = section.querySelector('.msg-body');
    if (!body) return;

    body.dataset.originalHtml = body.innerHTML;
    body.innerHTML = '';
    const textarea = document.createElement('textarea');
    textarea.className = 'edit-textarea';
    textarea.value = editText;
    textarea.dataset.originalText = editText;
    body.appendChild(textarea);

    textarea.addEventListener('input', () => {
      textarea.style.height = 'auto';
      textarea.style.height = Math.max(80, textarea.scrollHeight) + 'px';
    });
    textarea.addEventListener('wheel', (e) => {
      e.stopPropagation();
      e.preventDefault();
      if (e.deltaMode === 0) {
        textarea.scrollTop += e.deltaY * 0.3;
      } else if (e.deltaMode === 1) {
        textarea.scrollTop += e.deltaY * 16;
      } else {
        textarea.scrollTop += e.deltaY * 100;
      }
    }, { passive: false });
    textarea.style.height = Math.max(80, textarea.scrollHeight + 20) + 'px';
    textarea.focus();

    /* Replace center controls with edit buttons */
    const footer = section.querySelector('.msg-footer');
    if (footer) {
      footer.dataset.originalHtml = footer.innerHTML;
      footer.innerHTML = '';

      const metaCol = document.createElement('div');
      metaCol.className = 'msg-meta';
      footer.appendChild(metaCol);

      const center = document.createElement('div');
      center.className = 'msg-center-controls';
      footer.appendChild(center);

      const editBox = document.createElement('div');
      editBox.className = 'edit-buttons';
      editBox.innerHTML = `
        <div class="edit-btn cancel" data-action="edit-cancel" data-message-id="${messageId}" title="Cancel">
          <svg viewBox="0 0 24 24"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
        </div>
        <div class="edit-btn save" data-action="edit-save" data-message-id="${messageId}" title="Save">
          <svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>
        </div>
      `;
      footer.appendChild(editBox);
    }

    this.virtualList.container.scrollTop = scrollPos;
  }

  stopEdit(messageId) {
    const section = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!section) return;
    section.classList.remove('editing');

    const body = section.querySelector('.msg-body');
    if (body && body.dataset.originalHtml !== undefined) {
      body.innerHTML = body.dataset.originalHtml;
      delete body.dataset.originalHtml;
    }
    const footer = section.querySelector('.msg-footer');
    if (footer && footer.dataset.originalHtml !== undefined) {
      footer.innerHTML = footer.dataset.originalHtml;
      delete footer.dataset.originalHtml;
    }
  }

  setBackgroundImage(url, blur, opacity) {
    let bg = document.getElementById('bg-layer');
    if (!bg) {
      bg = document.createElement('div');
      bg.id = 'bg-layer';
      document.body.insertBefore(bg, document.body.firstChild);
    }
    if (url) {
      bg.style.backgroundImage = `url('${url}')`;
      bg.style.display = 'block';
    } else {
      bg.style.backgroundImage = '';
      bg.style.display = 'none';
    }
    bg.style.filter = `blur(${blur || 0}px)`;
    bg.style.opacity = opacity != null ? opacity : 1;
  }

  /* ---------- Guided swipe inline ---------- */
  _toggleGuidedSwipe(messageId) {
    const section = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!section) return;

    const btn = section.querySelector('.msg-guided-swipe-btn');
    const existing = section.querySelector('.guided-swipe-container');
    if (existing) {
      existing.remove();
      btn?.classList.remove('active');
      return;
    }

    const container = document.createElement('div');
    container.className = 'guided-swipe-container';

    const main = document.createElement('div');
    main.className = 'guidance-main';
    main.innerHTML = `<div class="guidance-header">GUIDED SWIPE</div>`;
    const textarea = document.createElement('textarea');
    textarea.className = 'guided-swipe-textarea';
    textarea.placeholder = 'Enter OOC instruction for swipe...';
    textarea.rows = 1;
    main.appendChild(textarea);
    container.appendChild(main);

    const actions = document.createElement('div');
    actions.className = 'guided-swipe-actions';

    const cancel = document.createElement('div');
    cancel.className = 'guided-btn cancel';
    cancel.innerHTML = '<svg viewBox="0 0 24 24"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>';
    cancel.addEventListener('click', () => {
      container.remove();
      btn?.classList.remove('active');
    });
    actions.appendChild(cancel);

    const confirm = document.createElement('div');
    confirm.className = 'guided-btn confirm';
    confirm.innerHTML = '<svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>';
    confirm.addEventListener('click', () => {
      const guidance = textarea.value.trim();
      if (guidance) this._sendToFlutter('onGuidedSwipe', [messageId, guidance]);
      container.remove();
      btn?.classList.remove('active');
    });
    actions.appendChild(confirm);

    container.appendChild(actions);

    /* Insert after .msg-content-stack inside section (matches Vue layout) */
    const stack = section.querySelector('.msg-content-stack');
    if (stack && stack.parentNode === section) {
      section.insertBefore(container, stack.nextSibling);
    } else {
      section.appendChild(container);
    }

    btn?.classList.add('active');
    textarea.focus();
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

  setSelectionMode(enabled) { this.renderer.setSelectionMode(enabled); }

  _handleSelectionCheckbox(e) {
    const cb = e.target.closest('.selection-checkbox');
    if (!cb) return;
    e.stopPropagation();
    const id = cb.dataset.messageId;
    this.renderer.toggleMessageSelection(id);
    this._sendToFlutter('onSelectionChange', [JSON.stringify(this.renderer.getSelectedIds())]);
  }

  _setupImageClickForward() {
    this.virtualList.container.addEventListener('image-click', (e) => {
      this._sendToFlutter('onImageClick', [e.detail.src]);
    });
  }

  debugFormatter(text) {
    const formatted = this.renderer.formatter.format(text, false);
    document.title = 'DBG:' + formatted.substring(0, 200);
  }
}
