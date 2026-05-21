class GlazeBridge {
  constructor(renderer, virtualList) {
    this.renderer = renderer;
    this.virtualList = virtualList;

    // Register Flutter channel
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler = (name, ...args) => {
        this._sendToFlutter(name, args);
      };
    }

    // Listen for scroll events
    this._setupScrollListener();

    // Listen for user interactions
    this._setupInteractionListener();
  }

  _sendToFlutter(name, args) {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler(name, ...args);
    }
  }

  _setupScrollListener() {
    const container = this.virtualList.container;
    let scrollTimeout;

    container.addEventListener('scroll', () => {
      clearTimeout(scrollTimeout);
      scrollTimeout = setTimeout(() => {
        // Check if near top (load more)
        if (this.virtualList.isNearTop(100)) {
          this._sendToFlutter('onScrollTop', []);
        }
      }, 100);
    });
  }

  _setupInteractionListener() {
    document.body.addEventListener('click', (e) => {
      // Handle link clicks
      if (e.target.tagName === 'A' && e.target.href) {
        e.preventDefault();
        const href = e.target.href;
        this._sendToFlutter('onLinkClick', [href]);
      }

      // Handle image clicks
      if (e.target.tagName === 'IMG') {
        const src = e.target.src;
        this._sendToFlutter('onImageClick', [src]);
      }
    });
  }

  // Methods called from Flutter via evaluateJavascript
  renderMessage(messageData) {
    const element = this.renderer.renderMessage(messageData);

    if (messageData.position === 'top') {
      this.virtualList.prepend(messageData.id, element);
    } else {
      this.virtualList.append(messageData.id, element);
    }

    return true;
  }

  updateMessage(messageId, newText, isUser = false) {
    this.renderer.updateMessage(messageId, newText, isUser);
    return true;
  }

  removeMessage(messageId) {
    this.virtualList.remove(messageId);
    return true;
  }

  clearAll() {
    this.virtualList.clear();
    return true;
  }

  scrollToBottom() {
    this.virtualList.scrollToBottom();
    return true;
  }

  scrollToTop() {
    this.virtualList.scrollToTop();
    return true;
  }

  scrollToMessage(messageId) {
    this.virtualList.scrollToMessage(messageId);
    return true;
  }

  setSearch(query, activeIndex = -1) {
    this.renderer.setSearch(query, activeIndex);
    return true;
  }

  scrollToSearchMatch(index) {
    this.renderer.scrollToSearchMatch(index);
    return true;
  }

  applyTheme(theme) {
    const root = document.documentElement;
    Object.keys(theme).forEach(key => {
      const cssVar = `--${key}`;
      root.style.setProperty(cssVar, theme[key]);
    });
    return true;
  }

  getScrollInfo() {
    const container = this.virtualList.container;
    return {
      scrollTop: container.scrollTop,
      scrollHeight: container.scrollHeight,
      clientHeight: container.clientHeight,
      nearTop: this.virtualList.isNearTop(),
      nearBottom: this.virtualList.isNearBottom()
    };
  }

  isNearBottom() {
    return this.virtualList.isNearBottom();
  }

  isNearTop() {
    return this.virtualList.isNearTop();
  }
}

// Make bridge globally accessible for flutter_inappwebview
window.glazeBridge = null; // Will be set when ready

// Auto-initialize when Flutter bridge is ready
if (window.flutter_inappwebview) {
  window.flutter_inappwebview.ready.then(() => {
    console.log('Flutter InAppWebView ready');
  });
}
