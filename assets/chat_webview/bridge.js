class Bridge {
  constructor(renderer, virtualList) {
    this.renderer = renderer;
    this.virtualList = virtualList;
    this._pendingRequests = new Map();
    this._requestCounter = 0;
    this.isGenerating = false;
    this._setupScrollListener();
    this._setupInteractionListener();
    this._setupImageClickForward();
  }

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

  _setupInteractionListener() {
    document.addEventListener('click', (e) => {
      if (e.target.closest('.selection-checkbox')) {
        this._handleSelectionCheckbox(e);
        return;
      }

      const link = e.target.closest('a');
      if (link) {
        e.preventDefault();
        this._sendToFlutter('onLinkClick', [link.href]);
      }

      const img = e.target.closest('img');
      if (img && img.src) {
        this._sendToFlutter('onImageClick', [img.src]);
      }

      const menuBtn = e.target.closest('.meta-menu-btn');
      if (menuBtn) {
        const id = menuBtn.dataset.messageId;
        const msgEl = document.querySelector(`[data-message-id="${id}"]`);
        if (msgEl) {
          const isUser = msgEl.classList.contains('message-user');
          const contentEl = msgEl.querySelector('.message-content');
          let content = '';
          if (contentEl && contentEl.shadowRoot) {
            const msgDiv = contentEl.shadowRoot.querySelector('.glaze-message');
            content = msgDiv ? msgDiv.textContent : '';
          }
          this._sendToFlutter('onMessageContext', [JSON.stringify({ id, isUser, isSystem: false, content })]);
        }
        return;
      }

      const swipeBtn = e.target.closest('.swipe-btn');
      if (swipeBtn) {
        const action = swipeBtn.dataset.action;
        const id = swipeBtn.dataset.messageId;
        this._sendToFlutter('onSwipe', [JSON.stringify({ id, direction: action === 'swipe-right' ? 'right' : 'left' })]);
        return;
      }

      const regenBtn = e.target.closest('.regen-btn');
      if (regenBtn) {
        const id = regenBtn.dataset.messageId;
        this._sendToFlutter('onRegenerate', [id]);
        return;
      }

      const guidedBtn = e.target.closest('.guided-swipe-btn');
      if (guidedBtn) {
        const id = guidedBtn.dataset.messageId;
        this._toggleGuidedSwipe(id);
        return;
      }

      const memoryBadge = e.target.closest('[data-action="memory-click"]');
      if (memoryBadge) {
        this._sendToFlutter('onMemoryClick', [memoryBadge.dataset.messageId]);
        return;
      }

      const injectBadge = e.target.closest('[data-action="inject-click"]');
      if (injectBadge) {
        this._sendToFlutter('onInjectClick', [injectBadge.dataset.messageId]);
        return;
      }

      const hiddenToggle = e.target.closest('[data-action="toggle-hidden"]');
      if (hiddenToggle) {
        this._sendToFlutter('onToggleHidden', [hiddenToggle.dataset.messageId]);
        return;
      }

      const errorCopyBtn = e.target.closest('.error-copy-btn');
      if (errorCopyBtn) {
        const msgEl = document.querySelector(`[data-message-id="${errorCopyBtn.dataset.messageId}"]`);
        if (msgEl) {
          const raw = msgEl.dataset.rawText || '';
          try {
            navigator.clipboard.writeText(raw);
          } catch (_) {
            const ta = document.createElement('textarea');
            ta.value = raw;
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            ta.remove();
          }
          errorCopyBtn.textContent = '✓';
          setTimeout(() => { errorCopyBtn.textContent = '📋'; }, 1200);
        }
        return;
      }

      this._hideSelectionBar();
    });

    document.addEventListener('selectionchange', () => {
      const sel = window.getSelection();
      if (sel && sel.toString().trim().length > 0) {
        this._showSelectionBar(sel.toString().trim());
      } else {
        this._hideSelectionBar();
      }
    });

    document.addEventListener('contextmenu', (e) => {
      const msgEl = e.target.closest('.message');
      if (!msgEl) return;
      e.preventDefault();

      const id = msgEl.dataset.messageId;
      const isUser = msgEl.classList.contains('message-user');
      const isSystem = msgEl.classList.contains('message-system');

      const contentEl = msgEl.querySelector('.message-content');
      let content = '';
      if (contentEl && contentEl.shadowRoot) {
        const msgDiv = contentEl.shadowRoot.querySelector('.glaze-message');
        content = msgDiv ? msgDiv.textContent : '';
      }

      this._sendToFlutter('onMessageContext', [JSON.stringify({
        id, isUser, isSystem, content
      })]);
    });
  }

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

  setMessages(messagesJson) {
    this._suppressLoadMore = true;
    const container = document.getElementById('chat-container') || document.body;
    if (!container.classList.contains('layout-bubble') &&
        !container.classList.contains('layout-standard') &&
        !container.classList.contains('layout-cards')) {
      container.classList.add('layout-bubble');
    }

    this.renderer.resetDateTracking();
    const messages = JSON.parse(messagesJson);
    
    const ids = [];
    const elements = [];
    
    for (const msg of messages) {
      const rendered = this.renderer.renderMessage(msg);
      if (Array.isArray(rendered)) {
        for (const el of rendered) {
          if (el.dataset.messageId) {
            ids.push(el.dataset.messageId);
            elements.push(el);
          } else {
            ids.push(`__date_${el.dataset.dateSeparator || Date.now()}`);
            elements.push(el);
          }
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
    const msgEl = document.querySelector(`[data-message-id="${msg.id}"]`);
    if (!msgEl) return;

    const animate = !!msg.swipeDirection;
    if (msg.swipeDirection) {
      msgEl.dataset.swipeDirection = msg.swipeDirection;
    }

    if (msg.reasoning) {
      msgEl.dataset.reasoning = msg.reasoning;
    } else if (msg.reasoning === null || msg.reasoning === '') {
      delete msgEl.dataset.reasoning;
    }

    this.renderer.updateMessageContent(msgEl, msg.text, msg.reasoning || null, msg.isUser, msg.isTyping, animate);

    if (msg.isHidden !== undefined) {
      msgEl.classList.toggle('message-hidden', !!msg.isHidden);
      const eye = msgEl.querySelector('[data-action="toggle-hidden"]');
      if (msg.isHidden && !eye) {
        const header = msgEl.querySelector('.message-header');
        if (header) {
          const indicator = document.createElement('span');
          indicator.className = 'hidden-indicator';
          indicator.textContent = '👁';
          indicator.title = 'Hidden message — click to unhide';
          indicator.dataset.messageId = msg.id;
          indicator.dataset.action = 'toggle-hidden';
          const timeEl = header.querySelector('.message-time');
          if (timeEl) {
            header.insertBefore(indicator, timeEl);
          } else {
            header.appendChild(indicator);
          }
        }
      } else if (!msg.isHidden && eye) {
        eye.remove();
      }
    }

    if (msg.swipeTotal !== undefined && msg.swipeTotal > 1) {
      const swipeNav = msgEl.querySelector('.swipe-nav');
      const swipeLabel = swipeNav ? swipeNav.querySelector('.swipe-label') : null;
      if (swipeLabel) {
        swipeLabel.textContent = `${(msg.swipeIndex || 0) + 1}/${msg.swipeTotal}`;
      } else if (!swipeNav) {
        const right = msgEl.querySelector('.message-meta-right');
        if (right) {
          const nav = document.createElement('div');
          nav.className = 'swipe-nav';
          const prevBtn = document.createElement('button');
          prevBtn.className = 'swipe-btn';
          prevBtn.textContent = '‹';
          prevBtn.dataset.action = 'swipe-left';
          prevBtn.dataset.messageId = msg.id;
          nav.appendChild(prevBtn);
          const label = document.createElement('span');
          label.className = 'swipe-label';
          label.textContent = `${(msg.swipeIndex || 0) + 1}/${msg.swipeTotal}`;
          nav.appendChild(label);
          const nextBtn = document.createElement('button');
          nextBtn.className = 'swipe-btn';
          nextBtn.textContent = '›';
          nextBtn.dataset.action = 'swipe-right';
          nextBtn.dataset.messageId = msg.id;
          nav.appendChild(nextBtn);
          const menuBtn = right.querySelector('.meta-menu-btn');
          if (menuBtn) {
            right.insertBefore(nav, menuBtn);
          } else {
            right.appendChild(nav);
          }
        }
      }
    }
  }

  setLastMessage(newLastId) {
    const prevLast = document.querySelector('.message-assistant[data-is-last="true"]');
    if (prevLast) {
      delete prevLast.dataset.isLast;
      const right = prevLast.querySelector('.message-meta-right');
      if (right) {
        const regen = right.querySelector('.regen-btn');
        const guided = right.querySelector('.guided-swipe-btn');
        if (regen) regen.remove();
        if (guided) guided.remove();
      }
    }
    if (!newLastId) return;
    const newLast = document.querySelector(`[data-message-id="${newLastId}"]`);
    if (newLast && newLast.classList.contains('message-assistant') && !this.isGenerating) {
      newLast.dataset.isLast = 'true';
      const right = newLast.querySelector('.message-meta-right');
      if (right && !right.querySelector('.regen-btn')) {
        const regenBtn = document.createElement('button');
        regenBtn.className = 'regen-btn';
        regenBtn.dataset.messageId = newLastId;
        regenBtn.textContent = '↻';
        regenBtn.title = 'Regenerate';
        const menuBtn = right.querySelector('.meta-menu-btn');
        if (menuBtn) {
          right.insertBefore(regenBtn, menuBtn);
        } else {
          right.appendChild(regenBtn);
        }
      }
      if (right && !right.querySelector('.guided-swipe-btn')) {
        const guidedBtn = document.createElement('button');
        guidedBtn.className = 'guided-swipe-btn';
        guidedBtn.dataset.messageId = newLastId;
        guidedBtn.textContent = '🎯';
        guidedBtn.title = 'Guided swipe';
        const menuBtn = right.querySelector('.meta-menu-btn');
        if (menuBtn) {
          right.insertBefore(guidedBtn, menuBtn);
        } else {
          right.appendChild(guidedBtn);
        }
      }
    }
  }

  removeMessage(messageId) {
    this.virtualList.remove(messageId);
  }

  clearAll() {
    this._showLoadingScreen();
    this.virtualList.clear();
  }

  scrollToBottom() {
    this.virtualList.scrollToBottom();
  }

  scrollToMessage(messageId) {
    this.virtualList.scrollToMessage(messageId);
  }

  setSearch(query, activeIndex) {
    this.renderer.setSearch(query, activeIndex);
  }

  setChatFont(fontFamily, fontDataUrl, fontSize, letterSpacing) {
    const root = document.documentElement;
    if (fontSize != null) root.style.setProperty('--font-size', fontSize + 'px');
    if (letterSpacing != null) root.style.setProperty('--letter-spacing', letterSpacing + 'px');

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
      if (fontFamily) {
        root.style.setProperty('--font-family', fontFamily);
      } else {
        root.style.removeProperty('--font-family');
      }
    }
  }

  applyTheme(themeJson) {
    const theme = JSON.parse(themeJson);
    const container = document.getElementById('chat-container') || document.body;

    for (const [key, value] of Object.entries(theme)) {
      if (key === 'chat-layout') {
        container.classList.remove('layout-bubble', 'layout-standard', 'layout-cards');
        if (value) {
          container.classList.add(`layout-${value}`);
        }
        continue;
      }
      document.documentElement.style.setProperty(`--${key}`, value);
    }
  }

  setBottomPadding(px) {
    const container = document.getElementById('chat-container') || document.body;
    container.style.paddingBottom = px + 'px';
  }

  applyLayout(layout) {
    const container = document.getElementById('chat-container') || document.body;
    container.classList.remove('layout-bubble', 'layout-standard', 'layout-cards', 'layout-default', 'layout-system');
    const cls = layout || 'bubble';
    container.classList.add(`layout-${cls}`);
  }

  startEdit(messageId) {
    let msgEl = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!msgEl) {
      const vlEl = this.virtualList.messages.get(messageId);
      if (vlEl) {
        if (vlEl.parentNode !== this.virtualList.container) {
          this.virtualList.container.insertBefore(vlEl, this.virtualList._bottomSpacer);
        }
        msgEl = vlEl;
      }
    }
    if (!msgEl) return;

    const scrollPos = this.virtualList.container.scrollTop;
    const rawText = msgEl.dataset.rawText || '';
    const reasoning = msgEl.dataset.reasoning || '';
    let editText = rawText;
    if (reasoning) {
      editText = '<' + 'think>\n' + reasoning + '\n</' + 'think>\n' + rawText;
    }

    const contentEl = msgEl.querySelector('.message-content');
    if (!contentEl) return;
    let shadowRoot = contentEl.shadowRoot;
    if (!shadowRoot) {
      shadowRoot = contentEl.attachShadow({ mode: 'open' });
      const style = document.createElement('style');
      style.textContent = `.glaze-message { word-wrap: break-word; line-height: 1.6; } .edit-textarea { width: 100%; min-height: 80px; background: var(--bg-color, #1a1a2e); color: var(--text-color, #e0e0e0); font-size: var(--font-size, 15px); font-family: inherit; resize: vertical; outline: none; line-height: 1.6; border: 1px solid var(--primary-color, #7996CE); border-radius: 6px; padding: 8px; }`;
      shadowRoot.appendChild(style);
      const msgDiv = document.createElement('div');
      msgDiv.className = 'glaze-message';
      shadowRoot.appendChild(msgDiv);
    }
    const msgDiv = shadowRoot.querySelector('.glaze-message');
    if (!msgDiv) return;

    msgDiv.innerHTML = '';
    const textarea = document.createElement('textarea');
    textarea.className = 'edit-textarea';
    textarea.value = editText;
    textarea.dataset.originalText = editText;
    msgDiv.appendChild(textarea);

    textarea.addEventListener('input', () => {
      textarea.style.height = 'auto';
      textarea.style.height = Math.max(80, textarea.scrollHeight) + 'px';
    });
    textarea.addEventListener('wheel', (e) => {
      e.stopPropagation();
    }, { passive: true });
    textarea.style.height = Math.max(80, textarea.scrollHeight + 20) + 'px';
    textarea.focus();

    msgEl.classList.add('message-editing');

    const metaRow = msgEl.querySelector('.message-meta-right');
    if (metaRow) {
      metaRow.dataset.originalHtml = metaRow.innerHTML;
      metaRow.innerHTML = '';
      const cancelBtn = document.createElement('button');
      cancelBtn.className = 'edit-btn edit-cancel-btn';
      cancelBtn.textContent = '✖';
      cancelBtn.dataset.messageId = messageId;
      cancelBtn.addEventListener('click', () => this._sendToFlutter('onEditCancel', [messageId]));
      metaRow.appendChild(cancelBtn);

      const saveBtn = document.createElement('button');
      saveBtn.className = 'edit-btn edit-save-btn';
      saveBtn.textContent = '✔';
      saveBtn.dataset.messageId = messageId;
      saveBtn.addEventListener('click', () => {
        const text = textarea.value;
        this._sendToFlutter('onEditSave', [messageId, text]);
      });
      metaRow.appendChild(saveBtn);
    }

    this.virtualList.container.scrollTop = scrollPos;
  }

  stopEdit(messageId) {
    const msgEl = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!msgEl) return;
    msgEl.classList.remove('message-editing');
    const metaRow = msgEl.querySelector('.message-meta-right');
    if (metaRow && metaRow.dataset.originalHtml !== undefined) {
      metaRow.innerHTML = metaRow.dataset.originalHtml;
      delete metaRow.dataset.originalHtml;
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

  _toggleGuidedSwipe(messageId) {
    const msgEl = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!msgEl) return;

    const existing = msgEl.querySelector('.guided-swipe-container');
    if (existing) {
      existing.remove();
      return;
    }

    const container = document.createElement('div');
    container.className = 'guided-swipe-container';

    const textarea = document.createElement('textarea');
    textarea.className = 'guided-swipe-textarea';
    textarea.placeholder = 'Enter guidance for the next swipe...';
    container.appendChild(textarea);

    const btnRow = document.createElement('div');
    btnRow.className = 'guided-swipe-btns';

    const cancelBtn = document.createElement('button');
    cancelBtn.className = 'guided-swipe-cancel';
    cancelBtn.textContent = 'Cancel';
    cancelBtn.addEventListener('click', () => container.remove());
    btnRow.appendChild(cancelBtn);

    const sendBtn = document.createElement('button');
    sendBtn.className = 'guided-swipe-send';
    sendBtn.textContent = 'Swipe →';
    sendBtn.addEventListener('click', () => {
      const guidance = textarea.value.trim();
      if (guidance) {
        this._sendToFlutter('onGuidedSwipe', [messageId, guidance]);
      }
      container.remove();
    });
    btnRow.appendChild(sendBtn);

    container.appendChild(btnRow);

    const metaRow = msgEl.querySelector('.message-meta');
    if (metaRow) {
      metaRow.parentNode.insertBefore(container, metaRow.nextSibling);
    } else {
      msgEl.appendChild(container);
    }

    textarea.focus();
  }

  setPerformanceMode(enabled) {
    const container = document.getElementById('chat-container') || document.body;
    container.classList.toggle('perf-mode', !!enabled);
  }

  animateGenTime(messageId, targetTime) {
    const msgEl = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!msgEl) return;
    const badge = msgEl.querySelector('.gen-time-badge');
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

  setSelectionMode(enabled) {
    this.renderer.setSelectionMode(enabled);
  }

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