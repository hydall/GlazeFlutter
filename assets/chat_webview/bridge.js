/* ============================================================
 * Bridge — communication with Flutter side.
 * Selectors follow ChatMessage.vue's class naming (.message-section, .msg-*).
 * Flutter callHandler contract is preserved — useMessageActions lives in Dart.
 * ============================================================ */

class GenTimer {
  constructor(renderer) {
    this.renderer = renderer;
    this._interval = null;
    this._start = null;
  }

  _format(startTime) {
    const elapsedSeconds = (Date.now() - startTime) / 1000;
    const battery = !!(window.bridge && window.bridge.batterySaver);
    return (battery ? elapsedSeconds.toFixed(0) : elapsedSeconds.toFixed(1)) + 's';
  }

  start() {
    this.stop();
    this._start = Date.now();
    const battery = !!(window.bridge && window.bridge.batterySaver);
    const intervalMs = battery ? 1000 : 100;
    this._interval = setInterval(() => {
      const timeStr = this._format(this._start);
      const streamingEl = document.querySelector('[data-message-id="__streaming__"]')
        || document.querySelector('.message-section.char .msg-body .typing-container')?.closest('.message-section');
      if (streamingEl) {
        let wrapper = streamingEl.querySelector('.gen-time-wrapper');

        if (!wrapper) {
          const layout = streamingEl.classList.contains('layout-bubble') ? 'bubble' : 'default';
          const statContainer = streamingEl.querySelector(layout === 'bubble' ? '.bubble-meta' : '.msg-meta');
          if (statContainer) {
            const stat = this.renderer._createGenStat(timeStr, 0, layout === 'bubble' ? '2px' : '4px');
            if (layout === 'bubble') stat.style.marginRight = 'auto';
            statContainer.appendChild(stat);
            wrapper = stat.querySelector('.gen-time-wrapper');
          }
        }

        if (wrapper && wrapper.rollingNumber) {
          wrapper.rollingNumber.setValue(timeStr);
        } else {
          const badge = streamingEl.querySelector('.gen-time-badge');
          if (badge) badge.textContent = timeStr;
        }
      }
    }, intervalMs);
  }

  stop() {
    if (this._interval) {
      clearInterval(this._interval);
      this._interval = null;
    }
    this._start = null;
  }
}

class MessageUpdateBatcher {
  constructor() {
    this._pending = new Map();
    this._rafScheduled = false;
  }

  enqueue(id, updateFn) {
    this._pending.set(id, updateFn);
    if (!this._rafScheduled) {
      this._rafScheduled = true;
      requestAnimationFrame(() => this.flush());
    }
  }

  flush() {
    const batch = new Map(this._pending);
    this._pending.clear();
    this._rafScheduled = false;
    for (const [id, fn] of batch) {
      fn(id);
    }
  }

  hasPending() {
    return this._pending.size > 0;
  }
}

class SelectionManager {
  constructor(sendToFlutter) {
    this._sendToFlutter = sendToFlutter;
    this._selectionMode = false;
    this._selectedIds = new Set();
    this._selectedText = '';
    this._barCreated = false;
  }

  get selectionMode() { return this._selectionMode; }

  getSelectedIds() { return [...this._selectedIds]; }

  setSelectionMode(enabled) {
    if (enabled && document.querySelector('.message-section.editing')) return;
    this._selectionMode = !!enabled;
    if (!enabled) this._selectedIds.clear();
    document.querySelectorAll('.message-section').forEach(msgEl => {
      msgEl.classList.toggle('selection-mode', this._selectionMode);
      msgEl.classList.toggle('selected', this._selectedIds.has(msgEl.dataset.messageId));
    });
  }

  toggleMessageSelection(messageId) {
    if (this._selectedIds.has(messageId)) this._selectedIds.delete(messageId);
    else this._selectedIds.add(messageId);
    const msgEl = document.querySelector(`[data-message-id="${messageId}"]`);
    if (msgEl) {
      msgEl.classList.toggle('selected', this._selectedIds.has(messageId));
    }
  }

  exitIfEmpty() {
    if (this._selectedIds.size === 0) this.setSelectionMode(false);
  }

  handleClick(e) {
    if (!this._selectionMode) return false;
    const section = e.target.closest('.message-section');
    if (!section) return false;
    e.preventDefault();
    e.stopPropagation();
    const id = section.dataset.messageId;
    this.toggleMessageSelection(id);
    this._sendToFlutter('onSelectionChange', [JSON.stringify(this.getSelectedIds())]);
    this.exitIfEmpty();
    return true;
  }

  handleContextMenu(e) {
    if (e.target.closest('.message-section.editing')) return false;
    const section = e.target.closest('.message-section');
    if (!section) return false;

    const id = section.dataset.messageId;
    const isSelected = this._selectedIds.has(id);
    const onBody = !!e.target.closest('.msg-body');

    if (this._selectionMode && isSelected && onBody) {
      return false;
    }

    e.preventDefault();

    if (this._selectionMode) {
      this.toggleMessageSelection(id);
      this._sendToFlutter('onSelectionChange', [JSON.stringify(this.getSelectedIds())]);
      this.exitIfEmpty();
    } else {
      if (document.querySelector('.message-section.editing')) return false;
      this.setSelectionMode(true);
      this.toggleMessageSelection(id);
      this._sendToFlutter('onSelectionChange', [JSON.stringify(this.getSelectedIds())]);
    }
    return true;
  }

  handleSelectionChange() {
    const editing = document.querySelector('.message-section.editing');
    if (editing) { this._hideSelectionBar(); return; }

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
      this._barCreated = true;
    }
    this._selectedText = text;
    bar.style.display = 'flex';
  }

  _hideSelectionBar() {
    const bar = document.getElementById('selection-bar');
    if (bar) bar.style.display = 'none';
  }

  applyClassesToSection(section, classes) {
    if (this._selectionMode) classes.push('selection-mode');
    if (this._selectedIds.has(section.dataset.messageId || '')) classes.push('selected');
    return classes;
  }

  shouldHideActions() { return this._selectionMode; }

  hideSelectionBar() { this._hideSelectionBar(); }
}

class EditController {
  constructor(sendToFlutter) {
    this._sendToFlutter = sendToFlutter;
  }

  startEdit(messageId, scrollTopFn) {
    const section = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!section) return;

    const scrollPos = scrollTopFn();
    section.classList.add('editing');

    const rawText = (section.dataset.rawText || '').replace(/^<think\b[^>]*>[\s\S]*?<\/think>\s*/, '');
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
    textarea.addEventListener('touchmove', (e) => {
      e.stopPropagation();
    }, { passive: true });
    textarea.style.height = Math.max(80, textarea.scrollHeight + 20) + 'px';
    textarea.focus();

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

    scrollTopFn(scrollPos);
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

  handleSave(el) {
    const section = el.closest('.message-section');
    const ta = section ? section.querySelector('.edit-textarea') : null;
    this._sendToFlutter('onEditSave', [el.dataset.messageId, ta ? ta.value : '']);
  }

  handleCancel(el) {
    this._sendToFlutter('onEditCancel', [el.dataset.messageId]);
  }

  isEditing(section) {
    return section && section.classList.contains('editing');
  }
}

class SwipeGestureHandler {
  constructor(sendToFlutter, getContainer, isGeneratingFn, disableRegenFn) {
    this._sendToFlutter = sendToFlutter;
    this._getContainer = getContainer;
    this._isGenerating = isGeneratingFn;
    this._disableRegen = disableRegenFn || (() => false);
  }

  setup() {
    const THRESHOLD = 100;
    let startX = 0;
    let startY = 0;
    let activeBody = null;
    let activeSection = null;
    let scrollingVertical = false;
    const self = this;

    const reset = (body) => {
      body.style.transition = 'transform 0.3s ease';
      body.style.transform = '';
      setTimeout(() => { body.style.transition = ''; }, 300);
    };

    const animateOut = (body, after) => {
      body.style.opacity = '0';
      requestAnimationFrame(() => {
        body.style.transform = '';
        setTimeout(() => {
          body.style.transition = 'opacity 0.2s ease';
          body.style.opacity = '1';
          setTimeout(() => { body.style.transition = ''; }, 200);
          after();
        }, 50);
      });
    };

    const onStart = (e) => {
      if (self._isGenerating()) return;

      const path = e.composedPath ? e.composedPath() : (e.path || []);
      const isScrollableX = path.some(el => {
        if (el.nodeType === Node.ELEMENT_NODE) {
          const style = window.getComputedStyle(el);
          if (style.overflowX === 'auto' || style.overflowX === 'scroll') {
            if (el.scrollWidth > el.clientWidth) return true;
          }
        }
        return false;
      });
      if (isScrollableX) return;

      const section = e.target.closest?.('.message-section.char');
      if (!section) return;
      if (section.classList.contains('editing') || section.classList.contains('selection-mode')) return;
      const body = section.querySelector('.msg-body');
      if (!body) return;
      const t = e.touches ? e.touches[0] : e;
      startX = t.clientX;
      startY = t.clientY;
      scrollingVertical = false;
      activeSection = section;
      activeBody = body;
      body.style.transition = 'none';
    };

    const onMove = (e) => {
      if (!activeBody || !activeSection) return;
      const t = e.touches ? e.touches[0] : e;
      const dx = t.clientX - startX;
      const dy = t.clientY - startY;
      if (scrollingVertical) return;
      if (Math.abs(dy) > Math.abs(dx) && Math.abs(dy) > 10) {
        scrollingVertical = true;
        activeBody.style.transform = '';
        return;
      }

      const swipeId = parseInt(activeSection.dataset.swipeId || '0', 10);
      const swipeTotal = parseInt(activeSection.dataset.swipeTotal || '1', 10);
      const isLast = activeSection.dataset.isLast === 'true';
      const greetingTotal = parseInt(activeSection.dataset.greetingTotal || '0', 10);
      const isFirstMsg = activeSection.dataset.messageIndex === '0';
      const canSwitchGreeting = isFirstMsg && greetingTotal > 1;

      const blockLastRegen = isLast && self._disableRegen();
      if (dx < 0 && !canSwitchGreeting && (blockLastRegen || !isLast) && swipeId >= swipeTotal - 1) return;
      if (dx > 0 && !canSwitchGreeting && swipeId <= 0) return;

      if (e.cancelable) e.preventDefault();
      activeBody.style.transform = `translateX(${dx}px)`;
    };

    const onEnd = (e) => {
      if (!activeBody || !activeSection) return;
      const body = activeBody;
      const section = activeSection;
      activeBody = null;
      activeSection = null;
      if (scrollingVertical) { body.style.transform = ''; body.style.transition = ''; return; }

      const t = e.changedTouches ? e.changedTouches[0] : e;
      const dx = t.clientX - startX;

      const swipeId = parseInt(section.dataset.swipeId || '0', 10);
      const swipeTotal = parseInt(section.dataset.swipeTotal || '1', 10);
      const isLast = section.dataset.isLast === 'true';
      const greetingTotal = parseInt(section.dataset.greetingTotal || '0', 10);
      const isFirstMsg = section.dataset.messageIndex === '0';
      const canSwitchGreeting = isFirstMsg && greetingTotal > 1;
      const msgId = section.dataset.messageId;

      if (canSwitchGreeting) {
        if (dx < -THRESHOLD) animateOut(body, () => self._sendToFlutter('onChangeGreeting', [msgId, 1]));
        else if (dx > THRESHOLD) animateOut(body, () => self._sendToFlutter('onChangeGreeting', [msgId, -1]));
        else reset(body);
        return;
      }

      if (dx < -THRESHOLD) {
        if (swipeId < swipeTotal - 1) {
          animateOut(body, () => self._sendToFlutter('onSwipe', [JSON.stringify({ id: msgId, direction: 'right' })]));
        } else if (isLast && !self._disableRegen()) {
          body.style.transition = 'transform 0.1s';
          body.style.transform = 'translateX(-20px)';
          setTimeout(() => {
            body.style.transform = '';
            body.style.transition = '';
            self._sendToFlutter('onRegenerate', [msgId, 'new_variant']);
          }, 100);
        } else {
          reset(body);
        }
      } else if (dx > THRESHOLD) {
        if (swipeId > 0) {
          animateOut(body, () => self._sendToFlutter('onSwipe', [JSON.stringify({ id: msgId, direction: 'left' })]));
        } else {
          reset(body);
        }
      } else {
        reset(body);
      }
    };

    const container = this._getContainer();
    container.addEventListener('touchstart', onStart, { passive: true });
    container.addEventListener('touchmove', onMove, { passive: false });
    container.addEventListener('touchend', onEnd);
    container.addEventListener('touchcancel', onEnd);
  }

  toggleGuidedSwipe(messageId) {
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

    const self = this;
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
      if (guidance) self._sendToFlutter('onGuidedSwipe', [messageId, guidance]);
      container.remove();
      btn?.classList.remove('active');
    });
    actions.appendChild(confirm);

    container.appendChild(actions);

    const stack = section.querySelector('.msg-content-stack');
    if (stack && stack.parentNode === section) {
      section.insertBefore(container, stack.nextSibling);
    } else {
      section.appendChild(container);
    }

    btn?.classList.add('active');
    textarea.focus();
  }
}

class InteractionDispatch {
  constructor(bridge) {
    this.bridge = bridge;
  }

  handleClick(e) {
    const bridge = this.bridge;

    if (bridge._selectionManager.handleClick(e)) return;

    const reasoningHdr = e.target.closest('[data-action="toggle-reasoning"]');
    if (reasoningHdr) {
      const block = reasoningHdr.closest('.msg-reasoning');
      if (block) block.classList.toggle('collapsed');
      return;
    }

    const actionEl = e.target.closest('[data-action]');
    if (actionEl) {
      const action = actionEl.dataset.action;
      const handler = this._actionMap[action];
      if (handler) {
        handler.call(this, e, actionEl);
        return;
      }
    }

    const link = e.target.closest('a');
    if (link) {
      e.preventDefault();
      bridge._sendToFlutter('onLinkClick', [link.href]);
      return;
    }

    const stopBtn = e.target.closest('.stop-btn');
    if (stopBtn) {
      bridge._sendToFlutter('onStop', []);
      return;
    }

    const regenBtn = e.target.closest('.msg-regenerate');
    if (regenBtn) {
      const id = regenBtn.dataset.messageId;
      const mode = regenBtn.dataset.mode || 'magic';
      bridge._sendToFlutter('onRegenerate', [id, mode]);
      return;
    }

    const guidedBtn = e.target.closest('.msg-guided-swipe-btn');
    if (guidedBtn) {
      bridge._swipeHandler.toggleGuidedSwipe(guidedBtn.dataset.messageId);
      return;
    }

    const actionsBtn = e.target.closest('.msg-actions-btn');
    if (actionsBtn) {
      const id = actionsBtn.dataset.messageId;
      const section = document.querySelector(`[data-message-id="${id}"]`);
      if (section) {
        const isUser = section.classList.contains('user');
        const isSystem = section.classList.contains('system');
        const content = bridge._extractText(section);
        bridge._sendToFlutter('onMessageContext', [JSON.stringify({ id, isUser, isSystem, content })]);
      }
      return;
    }

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

    const avatar = e.target.closest('.msg-avatar');
    if (avatar) {
      const img = avatar.querySelector('img');
      if (img && img.src) bridge._sendToFlutter('onImageClick', [img.src]);
      return;
    }

    const img = e.target.closest('.msg-image-attachment img');
    if (img && img.src) {
      bridge._sendToFlutter('onImageClick', [img.src]);
      return;
    }

    bridge._selectionManager.hideSelectionBar();
  }

  _extractImgInstruction(el, path) {
    const sec = path.find(e => e.dataset?.messageId);
    const messageId = sec ? sec.dataset.messageId : '';
    let instr = '';
    try { instr = decodeURIComponent(el.dataset.instruction || ''); }
    catch (_) { instr = el.dataset.instruction || ''; }
    return { instr, messageId };
  }

  get _actionMap() {
    const bridge = this.bridge;
    return {
      'memory-click': (e, el) => bridge._sendToFlutter('onMemoryClick', [el.dataset.messageId]),
      'inject-click': (e, el) => bridge._sendToFlutter('onInjectClick', [el.dataset.messageId]),
      'ext-blocks-click': (e, el) => bridge._sendToFlutter('onExtBlocksClick', [el.dataset.messageId]),
      'ext-block-stop': (e, el) => bridge._sendToFlutter('onExtBlockStop', [el.dataset.blockId, el.dataset.messageId]),
      'ext-block-regen': (e, el) => bridge._sendToFlutter('onExtBlockRegen', [el.dataset.blockId, el.dataset.messageId]),
      'toggle-hidden': (e, el) => bridge._sendToFlutter('onToggleHidden', [el.dataset.messageId]),
      'toggle-image-hidden': (e, el) => {
        const section = el.closest('.message-section');
        bridge._sendToFlutter('onToggleImageHidden', [section ? section.dataset.messageId : '']);
      },
      'swipe-left': (e, el) => bridge._sendToFlutter('onSwipe', [JSON.stringify({ id: el.dataset.messageId, direction: 'left' })]),
      'swipe-right': (e, el) => bridge._sendToFlutter('onSwipe', [JSON.stringify({ id: el.dataset.messageId, direction: 'right' })]),
      'greeting-prev': (e, el) => bridge._sendToFlutter('onChangeGreeting', [el.dataset.messageId, -1]),
      'greeting-next': (e, el) => bridge._sendToFlutter('onChangeGreeting', [el.dataset.messageId, 1]),
      'stop': (e, el) => bridge._sendToFlutter('onStop', []),
      'regenerate': (e, el) => bridge._sendToFlutter('onRegenerate', [el.dataset.messageId, el.dataset.mode || 'magic']),
      'toggle-guided': (e, el) => bridge._swipeHandler.toggleGuidedSwipe(el.dataset.messageId),
      'edit-save': (e, el) => bridge._editController.handleSave(el),
      'edit-cancel': (e, el) => bridge._editController.handleCancel(el),
      'open-actions': (e, el) => {
        const id = el.dataset.messageId;
        const section = document.querySelector(`[data-message-id="${id}"]`);
        if (section) {
          const isUser = section.classList.contains('user');
          const isSystem = section.classList.contains('system');
          const content = bridge._extractText(section);
          bridge._sendToFlutter('onMessageContext', [JSON.stringify({ id, isUser, isSystem, content })]);
        }
      },
      'img-retry': (e, el) => {
        const { instr, messageId } = this._extractImgInstruction(el, e.composedPath());
        bridge._sendToFlutter('onImgRetry', [instr, messageId]);
      },
      'img-find': (e, el) => {
        const { instr, messageId } = this._extractImgInstruction(el, e.composedPath());
        bridge._sendToFlutter('onImgFind', [instr, messageId]);
      },
      'img-regen': (e, el) => {
        const { instr, messageId } = this._extractImgInstruction(el, e.composedPath());
        bridge._sendToFlutter('onImgRegen', [instr, messageId]);
      },
      'img-stop': (e, el) => bridge._sendToFlutter('onImgCancel', []),
    };
  }
}

class Bridge {
  constructor(renderer, virtualList) {
    this.renderer = renderer;
    this.virtualList = virtualList;
    this._pendingRequests = new Map();
    this._requestCounter = 0;
    this.isGenerating = false;
    this.isGeneratingImage = false;
    this._genTimer = new GenTimer(renderer);
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
    this._setupScrollListener();
    this._setupInteractionListener();
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
      // Per-message stored persona wins; otherwise use the active identity.
      const newName = isUser
        ? (stored || this._personaName || 'You')
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
      } else if (!existingImg) {
        avatar.textContent = (newName.charAt(0) || '?').toUpperCase();
      }
    });
  }

  setGenerating(value) {
    this.isGenerating = value;
    if (value) {
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
      const show = distanceFromBottom > 240;
      if (lastShowScrollToBottom === show) return;
      lastShowScrollToBottom = show;
      this._sendToFlutter('onScrollToBottomVisibility', [show]);
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
          this._sendToFlutter('onHeaderScroll', [true]);
        }
      } else if (st < headerLastTop - 3) {
        if (headerHidden) {
          headerHidden = false;
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
  setMessages(messagesJson) {
    this.flush();
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
      for (const el of rendered) {
        const id = el.dataset.messageId || `__date_${el.dataset.dateSeparator || Date.now()}`;
        ids.push(id);
        elements.push(el);
      }
    }

    this.virtualList.setMessagesBatch(ids, elements);
    this._hideLoadingScreen();
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
      animate
    );

    if (msg.isHidden !== undefined) {
      section.classList.toggle('msg-hidden', !!msg.isHidden);
    }

    if (msg.swipeIndex !== undefined) section.dataset.swipeId = String(msg.swipeIndex);
    if (msg.swipeTotal !== undefined) section.dataset.swipeTotal = String(msg.swipeTotal);
    if (msg.greetingTotal !== undefined) section.dataset.greetingTotal = String(msg.greetingTotal);

    this._syncMessageControls(section, msg);

    this.renderer.updateMessageMeta(section, msg);
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
    const greetingIndex = msg.greetingIndex !== undefined ? msg.greetingIndex : 0;
    const greetingTotal = msg.greetingTotal !== undefined ? msg.greetingTotal : parseInt(section.dataset.greetingTotal || '0', 10);
    const messageIndex = parseInt(section.dataset.messageIndex || '-1', 10);
    const hasSwipes = isChar && swipeTotal > 1;
    const hasGreetings = isChar && messageIndex === 0 && greetingTotal > 1;
    const showRegen = ((!isChar && isLast) || isError) && !isGenerating && !isEditing;

    center.innerHTML = '';

    if (hasSwipes) {
      center.appendChild(this.renderer._createSwitcher(section.dataset.messageId, swipeIndex || 0, swipeTotal, 'swipe'));
    } else if (hasGreetings) {
      center.appendChild(this.renderer._createSwitcher(section.dataset.messageId, greetingIndex || 0, greetingTotal, 'greeting'));
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
      if (hasSwipes || hasGreetings) regen.classList.add('icon-only');
      regen.dataset.action = 'regenerate';
      regen.dataset.messageId = section.dataset.messageId;
      regen.dataset.mode = 'magic';
      regen.innerHTML = ICON.regen;
      if (!hasSwipes && !hasGreetings) {
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
    this.virtualList.clear();
  }

  scrollToBottom() {
    this.virtualList.scrollToBottom();
    requestAnimationFrame(() => {
      this._sendToFlutter('onScrollToBottomVisibility', [false]);
    });
  }
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
  }

  setBottomPadding(px) {
    const container = document.getElementById('chat-container') || document.body;
    container.style.paddingBottom = px + 'px';
    requestAnimationFrame(() => {
      const distanceFromBottom =
        container.scrollHeight - container.scrollTop - container.clientHeight;
      this._sendToFlutter('onScrollToBottomVisibility', [distanceFromBottom > 240]);
    });
  }

  setTopPadding(px) {
    const container = document.getElementById('chat-container') || document.body;
    container.style.paddingTop = px + 'px';
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
  }

  /* ---------- Inline edit (toggle into .msg-body) ---------- */
  startEdit(messageId) {
    this._editController.startEdit(messageId, (pos) => {
      if (pos !== undefined) this.virtualList.container.scrollTop = pos;
      return this.virtualList.container.scrollTop;
    });
  }

  stopEdit(messageId) {
    this._editController.stopEdit(messageId);
  }

  setBackgroundImage(url, blur, opacity) {
    // Background is handled by Flutter layer behind the transparent WebView.
  }

  setBackgroundNoise(opacity, intensity) {
    let noise = document.getElementById('bg-noise-layer');
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
    const op = Math.max(0, Math.min(1, opacity || 0));
    if (op <= 0) {
      noise.style.display = 'none';
      noise.style.backgroundImage = '';
      return;
    }
    const i = Math.max(0, Math.min(2, intensity == null ? 1 : intensity));
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
    const url = canvas.toDataURL('image/png');
    this._noiseCache.set(key, url);
    return url;
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

  // ── Ext Blocks panel ──────────────────────────────────────────────────────

  /**
   * Called from Flutter to show/update the inline ext-blocks panel under a
   * message. If `blocks` is empty the panel is removed.
   * @param {string} json  - JSON string: { messageId: string, blocks: Array }
   */
  showExtBlocksPanel(json) {
    let data;
    try { data = JSON.parse(json); } catch (_) { return; }
    const { messageId, blocks } = data;
    if (!messageId) return;

    const section = document.querySelector(`[data-message-id="${messageId}"]`);
    if (!section) return;

    let panel = section.querySelector('.ext-blocks-panel');

    if (!blocks || blocks.length === 0) {
      panel?.remove();
      return;
    }

    if (!panel) {
      panel = document.createElement('div');
      panel.className = 'ext-blocks-panel';
      const content = section.querySelector('.msg-content') || section;
      content.appendChild(panel);
    }

    panel.innerHTML = '';

    for (const block of blocks) {
      const item = document.createElement('div');
      item.className = `ext-block-item ${block.status || 'done'}`;

      // Header row
      const header = document.createElement('div');
      header.className = 'ext-block-header';

      const name = document.createElement('span');
      name.className = 'ext-block-name';
      name.textContent = block.blockName || block.blockId || '—';
      header.appendChild(name);

      const statusEl = document.createElement('span');
      statusEl.className = 'ext-block-status';
      statusEl.textContent = block.status || 'done';
      header.appendChild(statusEl);

      // Buttons
      const btnGroup = document.createElement('span');
      btnGroup.className = 'ext-block-actions';

      if (block.status === 'running') {
        const stopBtn = document.createElement('button');
        stopBtn.type = 'button';
        stopBtn.className = 'ext-block-btn';
        stopBtn.dataset.action = 'ext-block-stop';
        stopBtn.dataset.blockId = block.blockId;
        stopBtn.dataset.messageId = messageId;
        stopBtn.textContent = '■ Стоп';
        btnGroup.appendChild(stopBtn);
      } else {
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
      item.appendChild(header);

      // Content
      if (block.content) {
        const imgMatch = block.content.match(/\[IMG:RESULT:([^\]]+)\]/);
        if (imgMatch) {
          const img = document.createElement('img');
          let path = imgMatch[1];
          const pipeIdx = path.indexOf('|');
          if (pipeIdx !== -1) path = path.substring(0, pipeIdx);
          img.src = path.startsWith('file://') ? path : `file:///${path.replace(/\\/g, '/')}`;
          img.className = 'ext-block-image';
          item.appendChild(img);
        } else if (block.content.trim()) {
          const pre = document.createElement('div');
          pre.className = 'ext-block-content';
          pre.textContent = block.content;
          item.appendChild(pre);
        }
      }

      panel.appendChild(item);
    }
  }

  /**
   * Updates the panel if it's currently visible for this message.
   * Has the same signature as showExtBlocksPanel — just delegates.
   */
  updateExtBlocksPanel(json) {
    this.showExtBlocksPanel(json);
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
}
