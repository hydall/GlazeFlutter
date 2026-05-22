class Renderer {
  constructor(formatter, virtualList) {
    this.formatter = formatter;
    this.virtualList = virtualList;
    this.searchQuery = null;
    this.activeSearchIndex = -1;
    this.searchMatches = [];
  }

  renderMessage(messageData) {
    const { id, role, text, timestamp, displayName, avatarUrl, isUser, isAssistant, isSystem, isError, isTyping } = messageData;

    const messageEl = document.createElement('div');
    let className = `message ${this._getRoleClass(role)}`;
    if (isError) className += ' message-error';
    messageEl.className = className;
    messageEl.dataset.messageId = id;
    messageEl.dataset.rawText = text || '';
    if (messageData.reasoning) messageEl.dataset.reasoning = messageData.reasoning;

    const header = this._createHeader(messageData);
    messageEl.appendChild(header);

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
          color: var(--current-quote-color, var(--quote-color, #7996CE)) !important;
        }
        .glaze-message .chat-quote .chat-italic {
          color: inherit !important;
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

    this.updateMessageContent(messageEl, text, isUser, isTyping);

    if (role !== 'system') {
      const meta = this._createMetadata(messageData);
      messageEl.appendChild(meta);
    }

    return messageEl;
  }

  updateMessageContent(messageEl, text, isUser = false, isTyping = false) {
    const contentContainer = messageEl.querySelector('.message-content');
    if (!contentContainer || !contentContainer.shadowRoot) return;

    const shadowMessage = contentContainer.shadowRoot.querySelector('.glaze-message');
    if (!shadowMessage) return;

    try {
      if (isTyping && (!text || text.trim() === '')) {
        shadowMessage.innerHTML = '<div class="typing-indicator"><span class="typing-dot"></span><span class="typing-dot"></span><span class="typing-dot"></span></div>';
        return;
      }

      let formatted = this.formatter.format(text, isUser);

      if (this.searchQuery) {
        formatted = this._applySearchHighlight(formatted);
      }

      shadowMessage.innerHTML = formatted;
    } catch (e) {
      shadowMessage.textContent = text || '';
      console.error('Formatter error:', e);
    }
  }

  updateMessage(messageId, newText, isUser = false) {
    const messageEl = document.querySelector(`[data-message-id="${messageId}"]`);
    if (messageEl) {
      this.updateMessageContent(messageEl, newText, isUser);
    }
  }

  _createHeader(messageData) {
    const { role, displayName, personaName, avatarUrl, timestamp, avatarColor } = messageData;

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

    if (timestamp) {
      const time = document.createElement('div');
      time.className = 'message-time';
      time.textContent = this._formatTime(timestamp);
      header.appendChild(time);
    }

    return header;
  }

  _createMetadata(messageData) {
    const { genTime, tokens, triggeredLorebooks, triggeredMemories, swipeIndex, swipeTotal, id } = messageData;
    const hasLorebooks = (triggeredLorebooks || 0) + (triggeredMemories || 0) > 0;

    const row = document.createElement('div');
    row.className = 'message-meta';

    const left = document.createElement('div');
    left.className = 'message-meta-left';

    if (genTime) {
      const badge = document.createElement('span');
      badge.className = 'meta-badge';
      badge.textContent = `${genTime}`;
      left.appendChild(badge);
    }

    if (tokens && tokens > 0) {
      const badge = document.createElement('span');
      badge.className = 'meta-badge';
      badge.textContent = `${tokens}t`;
      left.appendChild(badge);
    }

    if (hasLorebooks) {
      const badge = document.createElement('span');
      badge.className = 'meta-badge meta-badge-inject';
      badge.textContent = `${(triggeredLorebooks || 0) + (triggeredMemories || 0)}`;
      badge.title = `Lorebooks: ${triggeredLorebooks || 0}, Memories: ${triggeredMemories || 0}`;
      left.appendChild(badge);
    }

    row.appendChild(left);

    const right = document.createElement('div');
    right.className = 'message-meta-right';

    if (swipeTotal > 1) {
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

  _applySearchHighlight(html) {
    if (!this.searchQuery) return html;

    this.searchMatches = [];
    let matchIndex = 0;

    const escapedQuery = this.searchQuery.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(`(${escapedQuery})`, 'gi');

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
          const text = messageContent.textContent;
          const isUser = messageEl.classList.contains('message-user');
          const formatted = this.formatter.format(text, isUser);
          const highlighted = this._applySearchHighlight(formatted);
          messageContent.innerHTML = highlighted;
        }
      }
    });
  }

  scrollToSearchMatch(index) {
    this.activeSearchIndex = index;
    this.setSearch(this.searchQuery, index);

    const activeMatch = document.querySelector('.search-highlight.active');
    if (activeMatch) {
      activeMatch.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }
}