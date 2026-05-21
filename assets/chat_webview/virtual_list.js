class VirtualList {
  constructor(container) {
    this.container = container;
    this.messages = new Map(); // messageId -> messageElement
    this.messageOrder = []; // ordered array of messageIds
  }

  clear() {
    this.messages.forEach(el => el.remove());
    this.messages.clear();
    this.messageOrder = [];
  }

  append(messageId, messageElement) {
    if (this.messages.has(messageId)) {
      // Update existing
      this.update(messageId, messageElement);
      return;
    }

    this.messages.set(messageId, messageElement);
    this.messageOrder.push(messageId);
    this.container.appendChild(messageElement);
  }

  prepend(messageId, messageElement) {
    if (this.messages.has(messageId)) {
      // Update existing
      this.update(messageId, messageElement);
      return;
    }

    this.messages.set(messageId, messageElement);
    this.messageOrder.unshift(messageId);

    if (this.container.firstChild) {
      this.container.insertBefore(messageElement, this.container.firstChild);
    } else {
      this.container.appendChild(messageElement);
    }
  }

  update(messageId, messageElement) {
    const existing = this.messages.get(messageId);
    if (existing && existing.parentNode) {
      existing.parentNode.replaceChild(messageElement, existing);
      this.messages.set(messageId, messageElement);
    }
  }

  remove(messageId) {
    const el = this.messages.get(messageId);
    if (el) {
      el.remove();
      this.messages.delete(messageId);
      this.messageOrder = this.messageOrder.filter(id => id !== messageId);
    }
  }

  scrollToBottom() {
    this.container.scrollTop = this.container.scrollHeight;
  }

  scrollToTop() {
    this.container.scrollTop = 0;
  }

  scrollToMessage(messageId) {
    const el = this.messages.get(messageId);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  getMessageCount() {
    return this.messages.size;
  }

  hasMessage(messageId) {
    return this.messages.has(messageId);
  }

  isNearBottom(threshold = 100) {
    const { scrollTop, scrollHeight, clientHeight } = this.container;
    return scrollHeight - scrollTop - clientHeight < threshold;
  }

  isNearTop(threshold = 100) {
    return this.container.scrollTop < threshold;
  }
}
