class Renderer {
  constructor(formatter, virtualList) {
    this.formatter = formatter;
    this.virtualList = virtualList;
    this.searchQuery = null;
    this.activeSearchIndex = -1;
    this.searchMatches = [];
    this._lastTimestamps = { date: null, idx: -1 };
    this._selectionMode = false;
    this._selectedIds = new Set();
  }

  setSelectionMode(enabled) {
    this._selectionMode = !!enabled;
    if (!enabled) this._selectedIds.clear();
    document.querySelectorAll('.message').forEach(msgEl => {
      msgEl.classList.toggle('selection-mode', this._selectionMode);
      const cb = msgEl.querySelector('.selection-checkbox');
      if (enabled && !cb) {
        const checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        checkbox.className = 'selection-checkbox';
        checkbox.dataset.messageId = msgEl.dataset.messageId;
        checkbox.checked = this._selectedIds.has(msgEl.dataset.messageId);
        msgEl.insertBefore(checkbox, msgEl.firstChild);
      } else if (!enabled && cb) {
        cb.remove();
      }
      msgEl.classList.toggle('selected', this._selectedIds.has(msgEl.dataset.messageId));
    });
  }

  toggleMessageSelection(messageId) {
    if (this._selectedIds.has(messageId)) {
      this._selectedIds.delete(messageId);
    } else {
      this._selectedIds.add(messageId);
    }
    const msgEl = document.querySelector(`[data-message-id="${messageId}"]`);
    if (msgEl) {
      msgEl.classList.toggle('selected', this._selectedIds.has(messageId));
      const cb = msgEl.querySelector('.selection-checkbox');
      if (cb) cb.checked = this._selectedIds.has(messageId);
    }
  }

  getSelectedIds() {
    return [...this._selectedIds];
  }

  renderMessage(messageData) {
    const { id, role, text, timestamp, displayName, avatarUrl, isUser, isAssistant, isSystem, isError, isTyping } = messageData;

    const elements = [];

    if (timestamp) {
      const dateStr = this._formatDate(timestamp);
      if (dateStr && dateStr !== this._lastTimestamps.date) {
        elements.push(this._createDateSeparator(dateStr));
        this._lastTimestamps = { date: dateStr, idx: 0 };
      }
    }

    const messageEl = document.createElement('div');
    let className = `message ${this._getRoleClass(role)}`;
    if (isError) className += ' message-error';
    if (messageData.isHidden) className += ' message-hidden';
    messageEl.className = className;
    messageEl.dataset.messageId = id;
    messageEl.dataset.rawText = text || '';
    if (messageData.reasoning) messageEl.dataset.reasoning = messageData.reasoning;

    const header = this._createHeader(messageData);
    messageEl.appendChild(header);

    if (messageData.imagePath) {
      const imgWrap = document.createElement('div');
      imgWrap.className = 'message-image-wrapper';
      const img = document.createElement('img');
      img.className = 'message-image';
      img.src = messageData.imagePath;
      img.loading = 'lazy';
      img.addEventListener('click', () => {
        this.virtualList.container.dispatchEvent(new CustomEvent('image-click', { detail: { src: messageData.imagePath } }));
      });
      imgWrap.appendChild(img);
      messageEl.appendChild(imgWrap);
    }

    if (messageData.guidanceText) {
      const guidanceBlock = document.createElement('div');
      guidanceBlock.className = 'guidance-block';
      const icon = document.createElement('span');
      icon.className = 'guidance-icon';
      icon.textContent = '🎯';
      guidanceBlock.appendChild(icon);
      const textEl = document.createElement('span');
      textEl.className = 'guidance-text';
      textEl.textContent = messageData.guidanceText;
      guidanceBlock.appendChild(textEl);
      messageEl.appendChild(guidanceBlock);
    }

    const contentContainer = document.createElement('div');
    contentContainer.className = 'message-content';
    messageEl.appendChild(contentContainer);

    if (!contentContainer.shadowRoot) {
      const shadow = contentContainer.attachShadow({ mode: 'open' });

      const style = document.createElement('style');
      style.textContent = `
        :host {
          display: block;
          font-size: inherit;
          color: inherit;
        }
        .glaze-message {
          word-wrap: break-word;
          line-height: 1.6;
          color: inherit;
        }
        .glaze-message p {
          margin-bottom: 0.8em;
        }
        .glaze-message p:last-child {
          margin-bottom: 0;
        }
        .glaze-message strong {
          font-weight: 700;
        }
        .glaze-message em {
          font-style: italic;
        }
        .glaze-message del {
          text-decoration: line-through;
        }
        .glaze-message code {
          background: rgba(0, 0, 0, 0.1);
          padding: 2px 6px;
          border-radius: 4px;
          font-family: monospace;
          font-size: 0.9em;
        }
        .glaze-message pre {
          background: rgba(0, 0, 0, 0.1);
          padding: 12px;
          border-radius: 8px;
          overflow-x: auto;
          margin: 12px 0;
        }
        .glaze-message pre code {
          background: none;
          padding: 0;
        }
        .glaze-message blockquote,
        .glaze-message .chat-blockquote {
          border-left: 3px solid var(--current-italic-color, var(--italic-color, #888));
          margin: 4px 0;
          padding: 2px 8px;
          color: var(--current-italic-color, var(--italic-color, #888));
          font-style: italic;
        }
        .glaze-message .chat-quote {
          color: var(--current-quote-color, var(--quote-color, #7996CE));
        }
        .glaze-message .chat-quote-text {
          color: var(--current-quote-color, var(--quote-color, #7996CE));
        }
        .glaze-message .font-color-block .chat-quote,
        .glaze-message .font-color-block .chat-quote-text {
          color: inherit;
        }
        .glaze-message .font-color-block .chat-italic {
          color: inherit;
        }
        .glaze-message .chat-italic {
          color: var(--current-italic-color, var(--italic-color, #888));
          font-style: italic;
        }
        .glaze-message a {
          color: var(--primary-color, #2196f3);
          text-decoration: underline;
        }
        .glaze-message img {
          max-width: 100%;
          height: auto;
          border-radius: 8px;
        }
        .glaze-message .search-highlight {
          background: #ffeb3b;
          padding: 2px 4px;
          border-radius: 4px;
        }
        .glaze-message .search-highlight.active {
          background: #ff9800;
          color: white;
        }
        .glaze-message .glaze-hc {
          font-weight: inherit;
        }
        .glaze-message .glaze-glow {
          font-weight: inherit;
        }
        .glaze-message .glaze-cg {
          font-weight: inherit;
        }
        .glaze-message .glaze-grad {
          font-weight: inherit;
        }
        .glaze-message .glaze-bg {
          color: #fff;
        }
        .glaze-message .glaze-mark {
          color: var(--current-quote-color, var(--quote-color, #7996CE));
        }
        .glaze-message .glaze-active {
          background: #ffeb3b;
          color: #000;
          padding: 2px 4px;
          border-radius: 4px;
        }
        .glaze-message .chat-quote-unclosed {
          color: var(--current-quote-color, var(--quote-color, #7996CE));
          opacity: 0.7;
        }
        .glaze-message .code-block-wrapper {
          position: relative;
          margin: 8px 0;
        }
        .glaze-message .code-lang {
          position: absolute;
          top: 4px;
          right: 8px;
          font-size: 10px;
          opacity: 0.4;
          text-transform: uppercase;
          font-family: monospace;
        }
        .glaze-message .janitor-img-wrapper {
          display: inline-block;
          max-width: 100%;
          margin: 4px 0;
        }
        .glaze-message .janitor-img-wrapper .janitor-img {
          max-width: 100%;
          border-radius: 8px;
          cursor: pointer;
        }
        .reasoning-block {
          margin: 8px 0;
          border: 1px solid var(--border-color, rgba(255,255,255,0.08));
          border-radius: 8px;
          overflow: hidden;
          font-size: 0.9em;
          opacity: 0.85;
        }
        .reasoning-summary {
          padding: 8px 12px;
          cursor: pointer;
          background: rgba(0,0,0,0.05);
          font-weight: 500;
          list-style: none;
        }
        .reasoning-summary::-webkit-details-marker {
          display: none;
        }
        .reasoning-summary::before {
          content: '▶';
          display: inline-block;
          margin-right: 6px;
          transition: transform 0.2s;
          font-size: 0.8em;
        }
        .reasoning-block[open] > .reasoning-summary::before {
          transform: rotate(90deg);
        }
        .reasoning-content {
          padding: 8px 12px;
          border-top: 1px solid var(--border-color, rgba(255,255,255,0.08));
          font-style: italic;
        }
        .glaze-message details {
          margin: 8px 0;
          border: 1px solid var(--border-color, rgba(255,255,255,0.08));
          border-radius: 8px;
          overflow: hidden;
          font-size: 0.95em;
          opacity: 0.9;
        }
        .glaze-message details summary {
          padding: 8px 12px;
          cursor: pointer;
          background: rgba(0,0,0,0.05);
          font-weight: 500;
          list-style: none !important;
          display: flex !important;
          align-items: center !important;
          gap: 6px;
          line-height: 1.4;
        }
        .glaze-message details summary::-webkit-details-marker {
          display: none !important;
        }
        .glaze-message details summary::marker {
          content: '' !important;
        }
        .glaze-message details summary::before {
          content: '▶';
          font-size: 0.75em;
          transition: transform 0.2s;
          flex-shrink: 0;
          line-height: 1;
          vertical-align: middle;
        }
        .glaze-message details summary > * {
          margin: 0;
        }
        .glaze-message details[open] > summary::before {
          transform: rotate(90deg);
        }
        .edit-textarea {
          width: 100%;
          min-height: 80px;
          max-height: 400px;
          padding: 8px;
          border: 1px solid rgba(255,255,255,0.12);
          border-radius: 8px;
          background: var(--bg-color, #1a1a2e);
          color: var(--text-color, #e0e0e0);
          font-size: var(--font-size, 15px);
          font-family: inherit;
          resize: vertical;
          outline: none;
          line-height: 1.6;
          overflow-y: auto;
          scrollbar-width: thin;
        }
        .edit-textarea:focus {
          border-color: var(--primary-color, #7996CE);
        }
      `;
      shadow.appendChild(style);

      const messageContent = document.createElement('div');
      messageContent.className = 'glaze-message';
      shadow.appendChild(messageContent);
    }

    this.updateMessageContent(messageEl, text, messageData.reasoning || null, isUser, isTyping);

    if (role !== 'system') {
      const meta = this._createMetadata(messageData);
      messageEl.appendChild(meta);
    }

    elements.push(messageEl);
    return elements.length > 1 ? elements : messageEl;
  }

  updateMessageContent(messageEl, text, reasoning = null, isUser = false, isTyping = false, animate = false) {
    const contentContainer = messageEl.querySelector('.message-content');
    if (!contentContainer || !contentContainer.shadowRoot) return;

    const shadowMessage = contentContainer.shadowRoot.querySelector('.glaze-message');
    if (!shadowMessage) return;

    try {
      if (isTyping && (!text || text.trim() === '') && (!reasoning || reasoning.trim() === '')) {
        shadowMessage.innerHTML = '<div class="typing-indicator"><span class="typing-dot"></span><span class="typing-dot"></span><span class="typing-dot"></span></div>';
        return;
      }

      let formatted = this.formatter.format(text, isUser);

      if (reasoning && reasoning.trim()) {
        const reasoningHtml = this.formatter.format(reasoning, isUser);
        formatted = `<details class="reasoning-block"><summary class="reasoning-summary">💭 Reasoning</summary><div class="reasoning-content">${reasoningHtml}</div></details>` + formatted;
      }

      if (this.searchQuery) {
        formatted = this._applySearchHighlight(formatted);
      }

      if (animate) {
        messageEl.classList.add('swipe-animating');
        const dir = messageEl.dataset.swipeDirection || 'left';
        messageEl.style.transform = dir === 'left' ? 'translateX(-30px)' : 'translateX(30px)';
        messageEl.style.opacity = '0.3';
        requestAnimationFrame(() => {
          messageEl.style.transition = 'transform 0.2s ease, opacity 0.2s ease';
          shadowMessage.innerHTML = formatted;
          messageEl.style.transform = '';
          messageEl.style.opacity = '';
          setTimeout(() => {
            messageEl.classList.remove('swipe-animating');
            messageEl.style.transition = '';
            delete messageEl.dataset.swipeDirection;
          }, 220);
        });
      } else {
        shadowMessage.innerHTML = formatted;
      }
    } catch (e) {
      shadowMessage.textContent = text || '';
      console.error('Formatter error:', e);
    }
  }

  updateMessage(messageId, newText, isUser = false, reasoning = null) {
    const messageEl = document.querySelector(`[data-message-id="${messageId}"]`);
    if (messageEl) {
      this.updateMessageContent(messageEl, newText, reasoning || messageEl.dataset.reasoning || null, isUser);
    }
  }

  _createHeader(messageData) {
    const { role, displayName, personaName, avatarUrl, timestamp, avatarColor, messageIndex, isHidden, memoryStatus, modelVersion } = messageData;

    const header = document.createElement('div');
    header.className = 'message-header';

    const finalName = displayName || personaName || this._getDefaultName(role);

    const avatar = document.createElement('div');
    avatar.className = 'message-avatar';

    if (avatarUrl) {
      const img = document.createElement('img');
      img.src = avatarUrl;
      img.alt = finalName;
      avatar.appendChild(img);
    } else {
      avatar.style.backgroundColor = avatarColor || '#555';
      avatar.textContent = (finalName || '?').charAt(0).toUpperCase();
    }

    header.appendChild(avatar);

    const nameEl = document.createElement('div');
    nameEl.className = 'message-name';
    nameEl.textContent = finalName;
    header.appendChild(nameEl);

    if (messageIndex != null) {
      const idx = document.createElement('span');
      idx.className = 'message-index';
      idx.textContent = `#${messageIndex + 1}`;
      header.appendChild(idx);
    }

    if (modelVersion) {
      const ver = document.createElement('sup');
      ver.className = 'version-badge';
      ver.textContent = modelVersion;
      header.appendChild(ver);
    }

    if (memoryStatus) {
      const badge = document.createElement('span');
      badge.className = `memory-badge memory-badge-${memoryStatus.toLowerCase()}`;
      badge.textContent = memoryStatus;
      if (messageData.triggeredMemories && messageData.triggeredMemories.length > 0) {
        badge.title = messageData.triggeredMemories.map(m => m.name).join(', ');
        badge.style.cursor = 'pointer';
        badge.dataset.messageId = messageData.id;
        badge.dataset.action = 'memory-click';
      }
      header.appendChild(badge);
    }

    if (isHidden) {
      const eye = document.createElement('span');
      eye.className = 'hidden-indicator';
      eye.textContent = '👁';
      eye.title = 'Hidden message — click to unhide';
      eye.dataset.messageId = messageData.id;
      eye.dataset.action = 'toggle-hidden';
      header.appendChild(eye);
    }

    if (timestamp) {
      const time = document.createElement('div');
      time.className = 'message-time';
      time.textContent = this._formatTime(timestamp);
      header.appendChild(time);
    }

    return header;
  }

  _createMetadata(messageData) {
    const { genTime, tokens, triggeredLorebooks, triggeredMemories, swipeIndex, swipeTotal, id, guidanceText, greetingIndex, isLast, isGenerating, isError, providerName } = messageData;
    const lorebooks = triggeredLorebooks || [];
    const memories = triggeredMemories || [];
    const hasInjects = lorebooks.length + memories.length > 0;

    const row = document.createElement('div');
    row.className = 'message-meta';

    const left = document.createElement('div');
    left.className = 'message-meta-left';

    if (genTime) {
      const badge = document.createElement('span');
      badge.className = 'meta-badge gen-time-badge';
      badge.textContent = `${genTime}`;
      left.appendChild(badge);
    }

    if (tokens && tokens > 0) {
      const badge = document.createElement('span');
      badge.className = 'meta-badge';
      badge.textContent = `${tokens}t`;
      left.appendChild(badge);
    }

    if (providerName) {
      const chip = document.createElement('span');
      chip.className = 'meta-badge provider-chip';
      chip.textContent = providerName;
      left.appendChild(chip);
    }

    if (hasInjects) {
      const badge = document.createElement('span');
      badge.className = 'meta-badge meta-badge-inject';
      badge.textContent = `${lorebooks.length + memories.length}`;
      const parts = [];
      if (lorebooks.length) parts.push(`WI: ${lorebooks.map(e => e.name).join(', ')}`);
      if (memories.length) parts.push(`Mem: ${memories.map(e => e.name).join(', ')}`);
      badge.title = parts.join('\n');
      badge.style.cursor = 'pointer';
      badge.dataset.messageId = messageData.id;
      badge.dataset.action = 'inject-click';
      left.appendChild(badge);
    }

    if (guidanceText) {
      const badge = document.createElement('span');
      badge.className = 'meta-badge meta-badge-guidance';
      badge.textContent = '🎯';
      badge.title = `Guidance: ${guidanceText}`;
      left.appendChild(badge);
    }

    row.appendChild(left);

    const right = document.createElement('div');
    right.className = 'message-meta-right';

    if (isError) {
      const copyBtn = document.createElement('button');
      copyBtn.className = 'error-copy-btn';
      copyBtn.dataset.messageId = id;
      copyBtn.textContent = '📋';
      copyBtn.title = 'Copy error';
      right.appendChild(copyBtn);
    }

    if (greetingIndex != null && swipeTotal > 1) {
      const greetNav = document.createElement('div');
      greetNav.className = 'swipe-nav greeting-nav';
      const prevBtn = document.createElement('button');
      prevBtn.className = 'swipe-btn';
      prevBtn.textContent = '‹';
      prevBtn.dataset.action = 'swipe-left';
      prevBtn.dataset.messageId = id;
      greetNav.appendChild(prevBtn);

      const label = document.createElement('span');
      label.className = 'swipe-label';
      label.textContent = `${(swipeIndex || 0) + 1}/${swipeTotal}`;
      greetNav.appendChild(label);

      const nextBtn = document.createElement('button');
      nextBtn.className = 'swipe-btn';
      nextBtn.textContent = '›';
      nextBtn.dataset.action = 'swipe-right';
      nextBtn.dataset.messageId = id;
      greetNav.appendChild(nextBtn);

      right.appendChild(greetNav);
    } else if (swipeTotal > 1) {
      const swipe = document.createElement('div');
      swipe.className = 'swipe-nav';
      const prevBtn = document.createElement('button');
      prevBtn.className = 'swipe-btn';
      prevBtn.textContent = '‹';
      prevBtn.dataset.action = 'swipe-left';
      prevBtn.dataset.messageId = id;
      swipe.appendChild(prevBtn);

      const label = document.createElement('span');
      label.className = 'swipe-label';
      label.textContent = `${(swipeIndex || 0) + 1}/${swipeTotal}`;
      swipe.appendChild(label);

      const nextBtn = document.createElement('button');
      nextBtn.className = 'swipe-btn';
      nextBtn.textContent = '›';
      nextBtn.dataset.action = 'swipe-right';
      nextBtn.dataset.messageId = id;
      swipe.appendChild(nextBtn);

      right.appendChild(swipe);
    }

    if (messageData.role === 'assistant' && isLast && !isGenerating) {
      const regenBtn = document.createElement('button');
      regenBtn.className = 'regen-btn';
      regenBtn.dataset.messageId = id;
      regenBtn.textContent = '↻';
      regenBtn.title = 'Regenerate';
      right.appendChild(regenBtn);

      const guidedBtn = document.createElement('button');
      guidedBtn.className = 'guided-swipe-btn';
      guidedBtn.dataset.messageId = id;
      guidedBtn.textContent = '🎯';
      guidedBtn.title = 'Guided swipe';
      right.appendChild(guidedBtn);
    }

    const menuBtn = document.createElement('button');
    menuBtn.className = 'meta-menu-btn';
    menuBtn.dataset.messageId = id;
    menuBtn.textContent = '⋮';
    right.appendChild(menuBtn);

    row.appendChild(right);

    return row;
  }

  _getRoleClass(role) {
    switch (role) {
      case 'user': return 'message-user';
      case 'assistant': return 'message-assistant';
      case 'system': return 'message-system';
      default: return 'message-assistant';
    }
  }

  _getDefaultName(role) {
    switch (role) {
      case 'user': return 'You';
      case 'assistant': return 'Assistant';
      case 'system': return 'System';
      default: return 'Unknown';
    }
  }

  _formatTime(timestamp) {
    if (!timestamp) return '';

    const date = new Date(timestamp);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  _formatDate(timestamp) {
    if (!timestamp) return null;
    const date = new Date(timestamp);
    const y = date.getFullYear();
    const m = (date.getMonth() + 1).toString().padStart(2, '0');
    const d = date.getDate().toString().padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  _formatDateDisplay(dateStr) {
    const date = new Date(dateStr + 'T00:00:00');
    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);

    if (date.toDateString() === today.toDateString()) return 'Today';
    if (date.toDateString() === yesterday.toDateString()) return 'Yesterday';

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return `${months[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}`;
  }

  _createDateSeparator(dateStr) {
    const el = document.createElement('div');
    el.className = 'date-separator';
    el.dataset.dateSeparator = dateStr;

    const line = document.createElement('div');
    line.className = 'date-separator-line';
    el.appendChild(line);

    const label = document.createElement('span');
    label.className = 'date-separator-label';
    label.textContent = this._formatDateDisplay(dateStr);
    el.appendChild(label);

    const line2 = document.createElement('div');
    line2.className = 'date-separator-line';
    el.appendChild(line2);

    return el;
  }

  resetDateTracking() {
    this._lastTimestamps = { date: null, idx: -1 };
  }

  _applySearchHighlight(html) {
    if (!this.searchQuery) return html;

    this.searchMatches = [];
    let matchIndex = 0;

    const escapedQuery = this.searchQuery.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(`(${escapedQuery})(?![^<]*>)`, 'gi');

    return html.replace(regex, (match) => {
      const isActive = matchIndex === this.activeSearchIndex;
      this.searchMatches.push(matchIndex);
      matchIndex++;

      return `<span class="search-highlight${isActive ? ' active' : ''}">${match}</span>`;
    });
  }

  setSearch(query, activeIndex = -1) {
    this.searchQuery = query;
    this.activeSearchIndex = activeIndex;

    const messages = document.querySelectorAll('.message');
    messages.forEach(messageEl => {
      const content = messageEl.querySelector('.message-content');
      if (content && content.shadowRoot) {
        const messageContent = content.shadowRoot.querySelector('.glaze-message');
        if (messageContent) {
          const rawText = messageEl.dataset.rawText || '';
          const isUser = messageEl.classList.contains('message-user');
          const formatted = this.formatter.format(rawText, isUser);
          const highlighted = this._applySearchHighlight(formatted);
          messageContent.innerHTML = highlighted;
        }
      }
    });

    if (activeIndex >= 0) {
      this._scrollToActiveMatch();
    }
  }

  _scrollToActiveMatch() {
    const messages = document.querySelectorAll('.message-content');
    for (const msgContent of messages) {
      if (msgContent.shadowRoot) {
        const active = msgContent.shadowRoot.querySelector('.search-highlight.active');
        if (active) {
          active.scrollIntoView({ behavior: 'smooth', block: 'center' });
          return;
        }
      }
    }
  }

  scrollToSearchMatch(index) {
    this.setSearch(this.searchQuery, index);
  }
}