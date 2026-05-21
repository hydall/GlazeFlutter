class Bridge {
  constructor(renderer, virtualList) {
    this.renderer = renderer;
    this.virtualList = virtualList;
    this._setupScrollListener();
    this._setupInteractionListener();
  }

  _sendToFlutter(name, args) {
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler(name, ...args);
    }
  }

  _setupScrollListener() {
    window.addEventListener('scroll', () => {
      if (this.virtualList.isNearTop(100)) {
        this._sendToFlutter('onLoadMore', []);
      }
    });
  }

  _setupInteractionListener() {
    document.addEventListener('click', (e) => {
      const link = e.target.closest('a');
      if (link) {
        e.preventDefault();
        this._sendToFlutter('onLinkClick', [link.href]);
      }

      const img = e.target.closest('img');
      if (img && img.src) {
        this._sendToFlutter('onImageClick', [img.src]);
      }
    });
  }

  setMessages(messagesJson) {
    const messages = JSON.parse(messagesJson);
    this.virtualList.clear();
    messages.forEach(msg => {
      const el = this.renderer.renderMessage(msg);
      this.virtualList.append(msg.id, el);
    });
  }

  appendMessage(messageJson) {
    const msg = JSON.parse(messageJson);
    const el = this.renderer.renderMessage(msg);
    this.virtualList.append(msg.id, el);
    this.virtualList.scrollToBottom();
  }

  appendMessages(messagesJson) {
    const messages = JSON.parse(messagesJson);
    messages.forEach(msg => {
      const el = this.renderer.renderMessage(msg);
      this.virtualList.append(msg.id, el);
    });
  }

  prependMessages(messagesJson) {
    const messages = JSON.parse(messagesJson);
    const scrollBefore = this.virtualList.container.scrollHeight;
    messages.forEach(msg => {
      const el = this.renderer.renderMessage(msg);
      this.virtualList.prepend(msg.id, el);
    });
    const scrollAfter = this.virtualList.container.scrollHeight;
    window.scrollTo(0, scrollAfter - scrollBefore);
  }

  updateMessage(messageJson) {
    const msg = JSON.parse(messageJson);
    this.renderer.updateMessage(msg);
  }

  removeMessage(messageId) {
    this.virtualList.remove(messageId);
  }

  clearAll() {
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

  applyTheme(themeJson) {
    const theme = JSON.parse(themeJson);
    for (const [key, value] of Object.entries(theme)) {
      document.documentElement.style.setProperty(`--${key}`, value);
    }
  }
}

window.bridge = null;
