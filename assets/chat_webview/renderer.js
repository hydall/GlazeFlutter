class Renderer {
  constructor(formatter, virtualList) {
    this.formatter = formatter;
    this.virtualList = virtualList;
    this.searchQuery = null;
    this.activeSearchIndex = -1;
    this.searchMatches = [];
  }

  renderMessage(messageData) {
    const { id, role, text, timestamp, displayName, avatarUrl, isUser, isAssistant, isSystem } = messageData;

    const messageEl = document.createElement('div');
    messageEl.className = `message ${this._getRoleClass(role)}`;
    messageEl.dataset.messageId = id;

    // Create header
    const header = this._createHeader(messageData);
    messageEl.appendChild(header);

    // Create content container with Shadow DOM
    const contentContainer = document.createElement('div');
    contentContainer.className = 'message-content';
    messageEl.appendChild(contentContainer);

    // Attach Shadow DOM if not already attached
    if (!contentContainer.shadowRoot) {
      const shadow = contentContainer.attachShadow({ mode: 'open' });

      // Inject styles into Shadow DOM
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
        .glaze-message blockquote {
          border-left: 4px solid var(--quote-color, #666);
          padding-left: 12px;
          margin: 12px 0;
          color: var(--quote-color, #666);
          font-style: italic;
        }
        .glaze-message .chat-quote {
          color: var(--quote-color, #666);
        }
        .glaze-message .chat-italic {
          color: var(--italic-color, #888);
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
      `;
      shadow.appendChild(style);

      const messageContent = document.createElement('div');
      messageContent.className = 'glaze-message';
      shadow.appendChild(messageContent);
    }

    // Format and set content
    this.updateMessageContent(messageEl, text, isUser);

    return messageEl;
  }

  updateMessageContent(messageEl, text, isUser = false) {
    const contentContainer = messageEl.querySelector('.message-content');
    if (!contentContainer || !contentContainer.shadowRoot) return;

    const shadowMessage = contentContainer.shadowRoot.querySelector('.glaze-message');
    if (!shadowMessage) return;

    // Format text
    let formatted = this.formatter.format(text, isUser);

    // Apply search highlighting if active
    if (this.searchQuery) {
      formatted = this._applySearchHighlight(formatted);
    }

    shadowMessage.innerHTML = formatted;
  }

  updateMessage(messageId, newText, isUser = false) {
    const messageEl = document.querySelector(`[data-message-id="${messageId}"]`);
    if (messageEl) {
      this.updateMessageContent(messageEl, newText, isUser);
    }
  }

  _createHeader(messageData) {
    const { role, displayName, avatarUrl, timestamp, avatarColor } = messageData;

    const header = document.createElement('div');
    header.className = 'message-header';

    // Avatar
    const avatar = document.createElement('div');
    avatar.className = 'message-avatar';

    if (avatarUrl) {
      avatar.style.backgroundImage = `url(${avatarUrl})`;
      avatar.style.backgroundSize = 'cover';
    } else {
      avatar.style.backgroundColor = avatarColor || '#ccc';
      avatar.textContent = (displayName || '?').charAt(0).toUpperCase();
    }

    header.appendChild(avatar);

    // Name
    const name = document.createElement('div');
    name.className = 'message-name';
    name.textContent = displayName || this._getDefaultName(role);
    header.appendChild(name);

    // Timestamp
    if (timestamp) {
      const time = document.createElement('div');
      time.className = 'message-time';
      time.textContent = this._formatTime(timestamp);
      header.appendChild(time);
    }

    return header;
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

    // Escape search query for regex
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

    // Re-render all messages with search
    const messages = document.querySelectorAll('.message');
    messages.forEach(messageEl => {
      const messageId = messageEl.dataset.messageId;
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
