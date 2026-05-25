/* ============================================================
 * Renderer — produces DOM matching Glaze/src/components/chat/ChatMessage.vue
 *
 * Root           .message-section[.user|.char|.system][.error][.selected][.selection-mode][.msg-hidden][.native-lite].layout-{bubble|standard|default|system}
 *   .msg-header    .msg-avatar  .msg-name (>.msg-name-label .msg-index.header-idx .item-version .msg-memory-badge .msg-lb-trigger-menu)  .msg-time
 *   .msg-guidance-block (optional)
 *   .msg-reasoning (optional) > .msg-reasoning-header / .msg-reasoning-content > .msg-transition-wrapper > .msg-reasoning-inner
 *   .msg-content-stack
 *     .msg-transition-wrapper > .msg-body (.error-window for errors, .typing-container for typing)
 *       (bubble layout) .bubble-meta — gen-stat / token-count-inline / bubble-time
 *     .msg-footer
 *       .msg-meta            — gen-stat (full layout only)
 *       .msg-center-controls — .msg-switcher / .msg-regenerate / .msg-guided-swipe-btn / .stop-btn
 *       .msg-actions-btn or .edit-buttons
 *   .guided-swipe-container (toggled by bridge)
 * ============================================================ */

/* SVG icon library — re-used from ChatMessage.vue */
const ICON = {
  hidden:    '<svg viewBox="0 0 24 24"><path d="M12 7c2.76 0 5 2.24 5 5 0 .65-.13 1.26-.36 1.83l2.92 2.92c1.51-1.26 2.7-2.89 3.43-4.75-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16C10.74 7.13 11.35 7 12 7zM2 4.27l2.28 2.28.46.46C3.08 8.3 1.78 10.02 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84l.42.42L19.73 22 21 20.73 3.27 3 2 4.27zM7.53 9.8l1.55 1.55c-.05.21-.08.43-.08.65 0 1.66 1.34 3 3 3 .22 0 .44-.03.65-.08l1.55 1.55c-.67.33-1.41.53-2.2.53-2.76 0-5-2.24-5-5 0-.79.2-1.53.53-2.2zm4.31-.78l3.15 3.15.02-.16c0-1.66-1.34-3-3-3l-.17.01z"/></svg>',
  eye:       '<svg viewBox="0 0 24 24"><path d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z"/></svg>',
  lbTrigger: '<svg viewBox="0 0 24 24"><path d="M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-1 9H9V9h10v2zm-4 4H9v-2h6v2zm4-8H9V5h10v2z"/></svg>',
  swipeLeft: '<svg viewBox="0 0 24 24"><path d="M15.41 7.41L14 6l-6 6 6 6 1.41-1.41L10.83 12z"/></svg>',
  swipeRight:'<svg viewBox="0 0 24 24"><path d="M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z"/></svg>',
  regen:     '<svg viewBox="0 0 24 24"><path d="M17.65 6.35C16.2 4.9 14.21 4 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08c-.82 2.33-3.04 4-5.65 4-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/></svg>',
  guided:    '<svg viewBox="0 0 24 24"><path d="M9 5v2h6.59L4 18.59 5.41 20 17 8.41V15h2V5H9z"/></svg>',
  menu:      '<svg viewBox="0 0 24 24"><path d="M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z"/></svg>',
  stop:      '<svg viewBox="0 0 24 24"><path d="M6 6h12v12H6z"/></svg>',
  edit:      '<svg viewBox="0 0 24 24"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>',
  save:      '<svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>',
  cancel:    '<svg viewBox="0 0 24 24"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>',
  copy:      '<svg viewBox="0 0 24 24"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>',
  clock:     '<svg viewBox="0 0 24 24"><path d="M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zM12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zm.5-13H11v6l5.25 3.15.75-1.23-4.5-2.67z"/></svg>',
  doc:       '<svg viewBox="0 0 24 24"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>',
  chevron:   '<svg class="reasoning-arrow" viewBox="0 0 24 24" style="width:16px;height:16px;fill:currentColor"><path d="M7 10l5 5 5-5z"/></svg>',
};

/* Style block injected into every shadow root */
const SHADOW_STYLE = `
  :host { display: block; font-size: inherit; color: inherit; }
  .glaze-message { word-wrap: break-word; line-height: 1.6; color: inherit; }
  .glaze-message p { margin: 0 0 0.8em 0; }
  .glaze-message p:first-child { margin-top: 0; }
  .glaze-message p:last-child { margin-bottom: 0; }
  .glaze-message strong { font-weight: 700; }
  .glaze-message em { font-style: italic; }
  .glaze-message del { text-decoration: line-through; }
  .glaze-message code {
    background: rgba(0,0,0,0.18);
    padding: 2px 6px;
    border-radius: 4px;
    font-family: 'Consolas','Monaco','Courier New',monospace;
    font-size: 0.9em;
  }
  .glaze-message pre {
    background: rgba(0,0,0,0.18);
    padding: 12px;
    border-radius: 8px;
    overflow-x: auto;
    margin: 12px 0;
  }
  .glaze-message pre code { background: none; padding: 0; }
  .glaze-message blockquote,
  .glaze-message .chat-blockquote {
    border-left: 3px solid var(--current-italic-color, var(--italic-color, #888));
    margin: 4px 0;
    padding: 2px 8px;
    color: var(--current-italic-color, var(--italic-color, #888));
    font-style: italic;
  }
  .glaze-message .chat-quote,
  .glaze-message .chat-quote-text {
    color: var(--current-quote-color, var(--quote-color, #7996CE));
  }
  .glaze-message .font-color-block .chat-quote,
  .glaze-message .font-color-block .chat-quote-text,
  .glaze-message .font-color-block .chat-italic { color: inherit; }
  .glaze-message .chat-italic {
    color: var(--current-italic-color, var(--italic-color, #888));
    font-style: italic;
  }
  .glaze-message a { color: var(--primary-color, #7996CE); text-decoration: underline; }
  .glaze-message img { max-width: 100%; height: auto; border-radius: 8px; margin: 8px 0; }
  .glaze-message .chat-quote-unclosed {
    color: var(--current-quote-color, var(--quote-color, #7996CE));
    opacity: 0.7;
  }
  .glaze-message .glaze-hc,
  .glaze-message .glaze-glow,
  .glaze-message .glaze-cg,
  .glaze-message .glaze-grad { font-weight: inherit; }
  .glaze-message .glaze-bg { color: #fff; }
  .glaze-message .glaze-mark { color: var(--current-quote-color, var(--quote-color, #7996CE)); }
  .glaze-message .glaze-active { background: #ffeb3b; color: #000; padding: 2px 4px; border-radius: 4px; }
  .glaze-message .font-style-block,
  .glaze-message .font-color-block { display: inline-block; vertical-align: baseline; color: inherit; }
  .glaze-message .code-block-wrapper { position: relative; margin: 8px 0; }
  .glaze-message .code-lang {
    position: absolute; top: 4px; right: 8px;
    font-size: 10px; opacity: 0.4;
    text-transform: uppercase; font-family: monospace;
  }
  .glaze-message .janitor-img-wrapper { display: inline-block; max-width: 100%; margin: 4px 0; }
  .glaze-message .janitor-img-wrapper .janitor-img {
    max-width: 100%; border-radius: 8px; cursor: pointer;
  }
  .glaze-message table tbody tr:nth-child(even) { background-color: rgba(255,255,255,0.02); }
  .glaze-message table td { padding: 8px 12px; border-bottom: 1px solid rgba(255,255,255,0.08); }
  .search-highlight-text {
    background-color: rgba(255, 215, 0, 0.4);
    color: #fff;
    border-radius: 4px;
    padding: 0 2px;
  }
  .search-highlight-text.active-search-match {
    background-color: rgba(244, 67, 54, 0.8);
    color: #fff;
  }
  .glaze-message details {
    margin: 8px 0;
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 8px;
    overflow: hidden;
    font-size: 0.95em;
    opacity: 0.9;
  }
  .glaze-message details summary {
    padding: 8px 12px;
    cursor: pointer;
    background: rgba(0,0,0,0.18);
    font-weight: 500;
    list-style: none !important;
    list-style-type: none !important;
    line-height: 1.4;
  }
  .glaze-message details summary::-webkit-details-marker { display: none !important; }
  .glaze-message details summary::marker { display: none !important; content: '' !important; }
  .glaze-message details summary::before { display: none !important; content: '' !important; }
  .glaze-message .glaze-arrow {
    display: inline;
    flex-shrink: 0;
    font-size: 1em;
    transition: transform 0.2s;
    opacity: 0.7;
    font-style: normal;
    font-weight: normal;
    user-select: none;
    -webkit-user-select: none;
  }
  .glaze-message .glaze-arrow.glaze-arrow-open { transform: rotate(90deg); }
  .search-highlight-text {
    background-color: rgba(255,215,0,0.4);
    border-radius: 4px;
    padding: 0 2px;
  }
  .search-highlight-text.active-search-match {
    background-color: rgba(244,67,54,0.8);
    color: #fff;
  }
  .edit-textarea {
    display: block;
    width: 100%;
    min-height: 80px;
    max-height: 60vh;
    overflow-y: auto;
    padding: 8px;
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 8px;
    background: var(--bg-color, #1a1a2e);
    color: var(--text-color, #e0e0e0);
    font-size: var(--font-size, 15px);
    font-family: inherit;
    resize: none;
    outline: none;
    line-height: 1.6;
  }
  .edit-textarea:focus { border-color: var(--primary-color, #7996CE); }
  .message-section.editing .msg-reasoning { display: none; }
`;

class Renderer {
  constructor(formatter, virtualList) {
    this.formatter = formatter;
    this.virtualList = virtualList;
    this.searchQuery = null;
    this.activeSearchIndex = -1;
    this.searchMatches = [];
    this._lastTimestamps = { date: null, idx: -1 };
    this.selectionManager = null;
  }

  /* ----- Public: render a message ----- */
  renderMessage(messageData) {
    const elements = [];

    if (messageData.timestamp) {
      const dateStr = this._formatDate(messageData.timestamp);
      if (dateStr && dateStr !== this._lastTimestamps.date) {
        elements.push(this._createDateSeparator(dateStr));
        this._lastTimestamps = { date: dateStr, idx: 0 };
      }
    }

    const messageEl = this._createSection(messageData);
    elements.push(messageEl);
    return elements;
  }

  _createSection(messageData) {
    const {
      id, role, text, reasoning,
      isError, isHidden, isLast, isTyping,
      guidanceText, guidanceType,
      imagePath, imageHidden,
    } = messageData;

    const layout = this._currentLayout();

    const section = document.createElement('div');
    section.dataset.messageId = id;
    section.dataset.rawText = text || '';
    if (reasoning) section.dataset.reasoning = reasoning;
    if (isLast && this._roleKey(role) === 'char') section.dataset.isLast = 'true';
    if (messageData.personaName) section.dataset.personaName = messageData.personaName;
    if (messageData.messageIndex != null) section.dataset.messageIndex = String(messageData.messageIndex);
    if (messageData.swipeIndex != null) section.dataset.swipeId = String(messageData.swipeIndex);
    if (messageData.swipeTotal != null) section.dataset.swipeTotal = String(messageData.swipeTotal);
    if (messageData.greetingTotal != null) section.dataset.greetingTotal = String(messageData.greetingTotal);

    const classes = ['message-section', this._roleKey(role), `layout-${layout}`];
    if (isError) classes.push('error');
    if (isHidden) classes.push('msg-hidden');
if (messageData.isEditing) classes.push('editing');
    if (this.selectionManager) this.selectionManager.applyClassesToSection(section, classes);
    section.className = classes.join(' ');

    /* --- Header --- */
    section.appendChild(this._createHeader(messageData));

    /* --- Guidance block (header-level) --- */
    if (guidanceText) {
      section.appendChild(this._createGuidanceBlock(guidanceText, guidanceType));
    }

    /* --- Reasoning --- */
    if (reasoning && reasoning.trim()) {
      section.appendChild(this._createReasoningBlock(reasoning, this._isUser(role)));
    }

    /* --- Content stack --- */
    const stack = document.createElement('div');
    stack.className = 'msg-content-stack';

    const wrapper = document.createElement('div');
    wrapper.className = 'msg-transition-wrapper';

    const body = document.createElement('div');
    body.className = 'msg-body';

    if (isTyping && (!text || !text.trim())) {
      body.appendChild(this._createTypingContainer());
    } else if (isError) {
      body.appendChild(this._createErrorWindow(messageData));
    } else {
      const content = this._createContentContainer();
      body.appendChild(content);
      this._writeShadowContent(content, text, this._isUser(role), false);
    }

    if (imagePath) {
      body.appendChild(this._createImageAttachment(imagePath, imageHidden));
    }

    if (layout === 'bubble') {
      body.appendChild(this._createBubbleMeta(messageData));
    }

    wrapper.appendChild(body);
    stack.appendChild(wrapper);

    /* --- Footer --- */
    stack.appendChild(this._createFooter(messageData));
    section.appendChild(stack);

    return section;
  }

  /* ----- Header ----- */
  _createHeader(m) {
    const header = document.createElement('div');
    header.className = 'msg-header';

    /* Avatar */
    const avatar = document.createElement('div');
    avatar.className = 'msg-avatar';
    const finalName = m.displayName || m.personaName || this._getDefaultName(m.role);
    if (m.avatarUrl) {
      const img = document.createElement('img');
      img.src = m.avatarUrl;
      img.alt = finalName;
      avatar.appendChild(img);
    } else {
      avatar.style.backgroundColor = m.avatarColor || '#555';
      avatar.textContent = (finalName || '?').charAt(0).toUpperCase();
    }
    header.appendChild(avatar);

    /* Name span */
    const nameEl = document.createElement('span');
    nameEl.className = 'msg-name';

    const label = document.createElement('span');
    label.className = 'msg-name-label';
    label.textContent = finalName;
    nameEl.appendChild(label);

    if (m.messageIndex != null) {
      const idx = document.createElement('span');
      idx.className = 'msg-index gen-stat header-idx';
      idx.textContent = `#${m.messageIndex + 1}`;
      nameEl.appendChild(idx);
    }

    if (m.modelVersion) {
      const ver = document.createElement('sup');
      ver.className = 'item-version';
      ver.textContent = `#${m.modelVersion}`;
      nameEl.appendChild(ver);
    }

    if (m.memoryStatus) {
      const badge = document.createElement('button');
      badge.type = 'button';
      const cls = this._memoryStatusClass(m.memoryStatus);
      badge.className = `msg-memory-badge ${cls}`;
      badge.dataset.action = 'memory-click';
      badge.dataset.messageId = m.id;
      badge.textContent = m.memoryStatus;
      nameEl.appendChild(badge);
    }

    const hasTriggers =
      (m.triggeredLorebooks && m.triggeredLorebooks.length) ||
      (m.triggeredMemories && m.triggeredMemories.length);
    if (hasTriggers) {
      const trig = document.createElement('div');
      trig.className = 'msg-lb-trigger-menu';
      trig.dataset.action = 'inject-click';
      trig.dataset.messageId = m.id;
      trig.innerHTML = ICON.lbTrigger;
      nameEl.appendChild(trig);
    }

    header.appendChild(nameEl);

    /* Time */
    const time = document.createElement('span');
    time.className = 'msg-time';
    if (m.isHidden) {
      const eye = document.createElement('span');
      eye.innerHTML = ICON.hidden;
      const svg = eye.firstChild;
      svg.classList.add('msg-hidden-badge');
      svg.dataset.action = 'toggle-hidden';
      svg.dataset.messageId = m.id;
      time.appendChild(svg);
    }
    if (m.timestamp) {
      time.appendChild(document.createTextNode(this._formatTime(m.timestamp)));
    }
    header.appendChild(time);

    return header;
  }

  /* ----- Guidance block ----- */
  _createGuidanceBlock(text, type) {
    const block = document.createElement('div');
    block.className = 'msg-guidance-block';

    const label = document.createElement('div');
    label.className = 'guidance-label';
    const labelText = document.createElement('span');
    labelText.textContent = `GUIDED ${(type || 'SWIPE').toUpperCase()}`;
    label.appendChild(labelText);

    const body = document.createElement('div');
    body.className = 'guidance-content';
    body.textContent = text;

    block.appendChild(label);
    block.appendChild(body);
    return block;
  }

  /* ----- Reasoning ----- */
  _createReasoningBlock(reasoning, isUser) {
    const block = document.createElement('div');
    block.className = 'msg-reasoning collapsed';

    const header = document.createElement('div');
    header.className = 'msg-reasoning-header';
    header.dataset.action = 'toggle-reasoning';
    header.innerHTML = `<span>Reasoning</span>${ICON.chevron}`;

    const content = document.createElement('div');
    content.className = 'msg-reasoning-content';
    const wrap = document.createElement('div');
    wrap.className = 'msg-transition-wrapper';
    const inner = document.createElement('div');
    inner.className = 'msg-reasoning-inner';

    const shadowHost = this._createContentContainer();
    inner.appendChild(shadowHost);
    this._writeShadowContent(shadowHost, reasoning, isUser, false);

    wrap.appendChild(inner);
    content.appendChild(wrap);

    block.appendChild(header);
    block.appendChild(content);
    return block;
  }

  /* ----- Error window ----- */
  _createErrorWindow(m) {
    const win = document.createElement('div');
    win.className = 'error-window';

    const hdr = document.createElement('div');
    hdr.className = 'error-header';

    const label = document.createElement('span');
    label.textContent = 'ERROR';
    hdr.appendChild(label);

    if (m.providerName) {
      const chip = document.createElement('span');
      chip.className = 'error-provider-chip';
      chip.textContent = `${m.providerName} API`;
      hdr.appendChild(chip);
    }

    const copyBtn = document.createElement('button');
    copyBtn.className = 'error-copy-btn';
    copyBtn.dataset.messageId = m.id;
    copyBtn.innerHTML = ICON.copy;
    hdr.appendChild(copyBtn);

    win.appendChild(hdr);

    const content = document.createElement('div');
    content.className = 'error-content';
    const host = this._createContentContainer();
    content.appendChild(host);
    this._writeShadowContent(host, m.text || '', this._isUser(m.role), false);
    win.appendChild(content);
    return win;
  }

  /* ----- Image attachment ----- */
  _createImageAttachment(src, hidden) {
    const wrap = document.createElement('div');
    wrap.className = 'msg-image-attachment' + (hidden ? ' image-hidden' : '');

    const img = document.createElement('img');
    img.src = src;
    img.alt = 'attachment';
    img.loading = 'lazy';
    wrap.appendChild(img);

    const toggle = document.createElement('div');
    toggle.className = 'image-ctx-toggle';
    toggle.dataset.action = 'toggle-image-hidden';
    toggle.innerHTML = hidden ? ICON.hidden : ICON.eye;
    wrap.appendChild(toggle);

    return wrap;
  }

  /* ----- Typing container ----- */
  _createTypingContainer() {
    const wrap = document.createElement('div');
    wrap.className = 'typing-container';
    wrap.innerHTML = `
      <svg class="typing-icon" viewBox="0 0 24 24"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>
      <span class="typing-text">Generating...</span>
    `;
    return wrap;
  }

  _createGenStat(genTime, tokenCount, clockMargin = '2px') {
    const stat = document.createElement('div');
    stat.className = 'gen-stat';
    const hasGen = genTime && genTime !== '0s';
    const hasTokens = tokenCount && tokenCount > 0;
    if (hasGen) {
      const clock = document.createElement('span');
      clock.innerHTML = ICON.clock;
      clock.firstChild.style.cssText = `width:12px;height:12px;fill:currentColor;margin-right:${clockMargin};`;
      stat.appendChild(clock.firstChild);
      const gw = document.createElement('span');
      gw.className = 'gen-time-wrapper';
      const gt = document.createElement('span');
      gt.className = 'gen-time gen-time-badge';
      gt.textContent = genTime;
      gw.appendChild(gt);
      stat.appendChild(gw);
    }
    if (hasTokens) {
      const tc = document.createElement('div');
      tc.className = 'token-count-inline';
      if (hasGen) tc.style.marginLeft = '6px';
      const doc = document.createElement('span');
      doc.innerHTML = ICON.doc;
      doc.firstChild.style.cssText = 'width:12px;height:12px;fill:currentColor;margin-right:2px;';
      tc.appendChild(doc.firstChild);
      const t = document.createElement('span');
      t.textContent = `${tokenCount}t`;
      tc.appendChild(t);
      stat.appendChild(tc);
    }
    return stat;
  }

  /* ----- Bubble meta (inside body) ----- */
  _createBubbleMeta(m) {
    const meta = document.createElement('div');
    meta.className = 'bubble-meta';

    if (m.messageIndex != null) {
      const idx = document.createElement('span');
      idx.className = 'msg-index gen-stat';
      idx.textContent = `#${m.messageIndex + 1}`;
      meta.appendChild(idx);
    }

    const hasGen = m.genTime && m.genTime !== '0s';
    const hasTokens = m.tokens && m.tokens > 0 && !m.isTyping;
    if (hasGen || hasTokens) {
      const stat = this._createGenStat(m.genTime, m.tokens, '2px');
      stat.style.marginRight = 'auto';
      meta.appendChild(stat);
    }

    const time = document.createElement('span');
    time.className = 'bubble-time';
    if (!hasGen && !hasTokens) time.style.marginLeft = 'auto';
    if (m.isHidden) {
      const hi = document.createElement('span');
      hi.innerHTML = ICON.hidden;
      hi.firstChild.classList.add('msg-hidden-badge');
      time.appendChild(hi.firstChild);
    }
    if (m.timestamp) {
      time.appendChild(document.createTextNode(this._formatTime(m.timestamp)));
    }
    meta.appendChild(time);

    return meta;
  }

  /* ----- Footer / controls ----- */
  _createFooter(m) {
    const footer = document.createElement('div');
    footer.className = 'msg-footer';

    /* --- Left meta (standard layout shows it; bubble hides via CSS) --- */
    const metaCol = document.createElement('div');
    metaCol.className = 'msg-meta';
    const hasGen = m.genTime && m.genTime !== '0s';
    const hasTokens = m.tokens && m.tokens > 0 && !m.isTyping;
    if (hasGen || hasTokens) {
      const stat = this._createGenStat(m.genTime, m.tokens, '4px');
      metaCol.appendChild(stat);
    }
    footer.appendChild(metaCol);

    /* --- Center controls --- */
    const center = document.createElement('div');
    center.className = 'msg-center-controls';

    const isChar = this._roleKey(m.role) === 'char';
    const hasSwipes = isChar && m.swipeTotal && m.swipeTotal > 1;
    const hasGreetings = isChar && m.messageIndex === 0 && m.greetingTotal && m.greetingTotal > 1;
    const showRegen = ((!isChar && m.isLast) || m.isError) && !m.isGenerating && !m.isEditing;

    if (hasSwipes) {
      center.appendChild(this._createSwitcher(m.id, m.swipeIndex || 0, m.swipeTotal, 'swipe'));
    } else if (hasGreetings) {
      center.appendChild(this._createSwitcher(m.id, m.greetingIndex || 0, m.greetingTotal, 'greeting'));
    }

    if (isChar && m.isLast && !m.isGenerating && !m.isEditing) {
      const guided = document.createElement('div');
      guided.className = 'msg-guided-swipe-btn';
      guided.dataset.action = 'toggle-guided';
      guided.dataset.messageId = m.id;
      guided.title = 'Guided swipe';
      guided.innerHTML = ICON.guided;
      center.appendChild(guided);
    }

    if (isChar && m.isLast && m.isGenerating) {
      const stop = document.createElement('button');
      stop.className = 'stop-btn';
      stop.dataset.action = 'stop';
      stop.dataset.messageId = m.id;
      stop.title = 'Stop';
      stop.innerHTML = ICON.stop;
      center.appendChild(stop);
    }

    if (showRegen) {
      const regen = document.createElement('div');
      regen.className = 'msg-regenerate';
      if (hasSwipes || hasGreetings) regen.classList.add('icon-only');
      regen.dataset.action = 'regenerate';
      regen.dataset.messageId = m.id;
      regen.dataset.mode = 'magic';
      regen.innerHTML = ICON.regen;
      if (!hasSwipes && !hasGreetings) {
        const span = document.createElement('span');
        span.textContent = '↻';
        // text label; Flutter side may localize
        span.textContent = 'Regenerate';
        regen.appendChild(span);
      }
      center.appendChild(regen);
    }

    footer.appendChild(center);

    /* --- Right: actions / edit buttons --- */
    if (m.isEditing) {
      footer.appendChild(this._createEditButtons(m.id));
    } else if (this.selectionManager && this.selectionManager.shouldHideActions()) {
      const actions = document.createElement('div');
      actions.className = 'msg-actions-btn';
      actions.dataset.action = 'open-actions';
      actions.dataset.messageId = m.id;
      actions.innerHTML = ICON.menu;
      footer.appendChild(actions);
    } else {
      // empty grid cell placeholder
      const ph = document.createElement('div');
      ph.style.gridColumn = '3';
      footer.appendChild(ph);
    }

    return footer;
  }

  _createSwitcher(messageId, index, total, kind) {
    const wrap = document.createElement('div');
    wrap.className = 'msg-switcher';
    wrap.dataset.kind = kind;

    const prev = document.createElement('div');
    prev.className = 'msg-switcher-btn prev';
    prev.dataset.action = kind === 'greeting' ? 'greeting-prev' : 'swipe-left';
    prev.dataset.messageId = messageId;
    prev.innerHTML = ICON.swipeLeft;
    wrap.appendChild(prev);

    const count = document.createElement('div');
    count.className = 'msg-switcher-count';
    count.textContent = `${index + 1}/${total}`;
    wrap.appendChild(count);

    const next = document.createElement('div');
    next.className = 'msg-switcher-btn next';
    next.dataset.action = kind === 'greeting' ? 'greeting-next' : 'swipe-right';
    next.dataset.messageId = messageId;
    next.innerHTML = ICON.swipeRight;
    wrap.appendChild(next);

    return wrap;
  }

  _createEditButtons(id) {
    const box = document.createElement('div');
    box.className = 'edit-buttons';

    const cancel = document.createElement('div');
    cancel.className = 'edit-btn cancel';
    cancel.dataset.action = 'edit-cancel';
    cancel.dataset.messageId = id;
    cancel.title = 'Cancel';
    cancel.innerHTML = ICON.cancel;
    box.appendChild(cancel);

    const save = document.createElement('div');
    save.className = 'edit-btn save';
    save.dataset.action = 'edit-save';
    save.dataset.messageId = id;
    save.title = 'Save';
    save.innerHTML = ICON.save;
    box.appendChild(save);

    return box;
  }

  /* ----- Shadow DOM content host ----- */
  _createContentContainer() {
    const host = document.createElement('div');
    host.className = 'message-content';
    if (!host.shadowRoot) {
      const shadow = host.attachShadow({ mode: 'open' });
      const style = document.createElement('style');
      style.textContent = SHADOW_STYLE;
      shadow.appendChild(style);
      const root = document.createElement('div');
      root.className = 'glaze-message';
      shadow.appendChild(root);
    }
    return host;
  }

  _writeShadowContent(host, text, isUser, isTyping) {
    if (!host || !host.shadowRoot) return;
    const root = host.shadowRoot.querySelector('.glaze-message');
    if (!root) return;
    try {
      if (isTyping && (!text || !text.trim())) {
        root.innerHTML = '';
        return;
      }
      let formatted = this.formatter.format(text || '', isUser);
      if (this.searchQuery) formatted = this._applySearchHighlight(formatted);
      root.innerHTML = formatted;
      this._fixDetailsSummaryArrows(root);
    } catch (e) {
      root.textContent = text || '';
      console.error('Formatter error:', e);
    }
  }

  _fixDetailsSummaryArrows(root) {
    root.querySelectorAll('details').forEach(details => {
      const summary = details.querySelector('summary');
      if (!summary || summary.querySelector('.glaze-flex-wrap')) return;

      // Wrap all existing summary children in a flex container.
      // This works even if WebView overrides display:flex on <summary> itself.
      const wrap = document.createElement('span');
      wrap.className = 'glaze-flex-wrap';
      wrap.style.cssText = 'display:flex;align-items:baseline;gap:6px;width:100%;';

      const arrow = document.createElement('span');
      arrow.className = 'glaze-arrow';
      arrow.setAttribute('aria-hidden', 'true');
      arrow.textContent = '▶';

      // Move all current children into wrap
      while (summary.firstChild) {
        wrap.appendChild(summary.firstChild);
      }
      // Prepend arrow inside wrap, then put wrap into summary
      wrap.insertBefore(arrow, wrap.firstChild);
      summary.appendChild(wrap);

      details.addEventListener('toggle', () => {
        arrow.classList.toggle('glaze-arrow-open', details.open);
      }, { once: false });
    });
  }

  /* ----- Public mutation API ----- */
  updateMessageContent(sectionEl, text, reasoning, isUser, isTyping, animate) {
    if (!sectionEl) return;
    const body = sectionEl.querySelector('.msg-body');
    if (!body) return;

    const isError = sectionEl.classList.contains('error');

    if (!isTyping && !isError && !animate) {
      const existingHost = body.querySelector('.message-content');
      if (existingHost && existingHost.shadowRoot) {
        const glazeMsg = existingHost.shadowRoot.querySelector('.glaze-message');
        if (glazeMsg) {
          glazeMsg.innerHTML = this.formatter.format(text, isUser);
          if (reasoning && reasoning.trim()) {
            let reasoningEl = sectionEl.querySelector('.msg-reasoning');
            if (reasoningEl) {
              const rHost = reasoningEl.querySelector('.msg-reasoning-inner .message-content');
              if (rHost) this._writeShadowContent(rHost, reasoning, isUser, false);
            }
          }
          return;
        }
      }
    }

    const meta = body.querySelector('.bubble-meta');
    const image = body.querySelector('.msg-image-attachment');
    body.innerHTML = '';

    if (isTyping && (!text || !text.trim())) {
      body.appendChild(this._createTypingContainer());
    } else if (isError) {
      body.appendChild(this._createErrorWindow({
        id: sectionEl.dataset.messageId,
        text: text,
        role: sectionEl.classList.contains('user') ? 'user' : 'char',
      }));
    } else {
      const host = this._createContentContainer();
      body.appendChild(host);
      this._writeShadowContent(host, text, isUser, false);
    }

    if (image) body.appendChild(image);
    if (meta) body.appendChild(meta);

    /* Reasoning is rendered outside body — handle separately */
    let reasoningEl = sectionEl.querySelector('.msg-reasoning');
    if (reasoning && reasoning.trim()) {
      if (!reasoningEl) {
        reasoningEl = this._createReasoningBlock(reasoning, isUser);
        const guidance = sectionEl.querySelector('.msg-guidance-block');
        sectionEl.insertBefore(reasoningEl, guidance ? guidance.nextSibling : sectionEl.querySelector('.msg-content-stack'));
      } else {
        const host = reasoningEl.querySelector('.msg-reasoning-inner .message-content');
        if (host) this._writeShadowContent(host, reasoning, isUser, false);
      }
    } else if (reasoningEl) {
      reasoningEl.remove();
    }

    if (animate) {
      sectionEl.classList.add('swipe-animating');
      const dir = sectionEl.dataset.swipeDirection || 'left';
      sectionEl.style.transform = dir === 'left' ? 'translateX(-30px)' : 'translateX(30px)';
      sectionEl.style.opacity = '0.3';
      requestAnimationFrame(() => {
        sectionEl.style.transition = 'transform 0.2s ease, opacity 0.2s ease';
        sectionEl.style.transform = '';
        sectionEl.style.opacity = '';
        setTimeout(() => {
          sectionEl.classList.remove('swipe-animating');
          sectionEl.style.transition = '';
          delete sectionEl.dataset.swipeDirection;
        }, 220);
      });
    }
  }

  updateMessage(messageId, newText, isUser = false, reasoning = null) {
    const el = document.querySelector(`[data-message-id="${messageId}"]`);
    if (el) {
      this.updateMessageContent(el, newText, reasoning || el.dataset.reasoning || null, isUser, false, false);
    }
  }

  updateMessageMeta(sectionEl, msg) {
    if (!sectionEl) return;

    const hasGen = msg.genTime && msg.genTime !== '0s';
    const hasTokens = msg.tokens && msg.tokens > 0 && !msg.isTyping;
    const hasTrigger = (msg.triggeredLorebooks && msg.triggeredLorebooks.length) ||
                       (msg.triggeredMemories && msg.triggeredMemories.length);
    const hasMemoryStatus = !!msg.memoryStatus;

    let bubbleMeta = sectionEl.querySelector('.bubble-meta');
    let footerMeta = sectionEl.querySelector('.msg-meta');

    if (hasGen || hasTokens) {
      let genStatBubble = bubbleMeta?.querySelector('.gen-stat');
      let genStatFooter = footerMeta?.querySelector('.gen-stat');

      if (hasGen) {
        const timeStr = msg.genTime;
        if (genStatBubble) {
          const badge = genStatBubble.querySelector('.gen-time-badge');
          if (badge) badge.textContent = timeStr;
        }
        if (genStatFooter) {
          const badge = genStatFooter.querySelector('.gen-time-badge');
          if (badge) badge.textContent = timeStr;
        }
      }

      if (hasTokens) {
        const tokenStr = `${msg.tokens}t`;
        if (genStatBubble) {
          const tc = genStatBubble.querySelector('.token-count-inline span:last-child');
          if (tc) tc.textContent = tokenStr;
        }
        if (genStatFooter) {
          const tc = genStatFooter.querySelector('.token-count-inline span:last-child');
          if (tc) tc.textContent = tokenStr;
        }
      }

      if (!genStatBubble && bubbleMeta && (hasGen || hasTokens)) {
        const stat = this._createGenStat(msg.genTime, msg.tokens, '2px');
        stat.style.marginRight = 'auto';
        bubbleMeta.appendChild(stat);
      }

      if (!genStatFooter && footerMeta && (hasGen || hasTokens)) {
        const stat = this._createGenStat(msg.genTime, msg.tokens, '4px');
        footerMeta.appendChild(stat);
      }
    }

    if (hasTrigger) {
      const nameEl = sectionEl.querySelector('.msg-name');
      if (nameEl) {
        let trig = nameEl.querySelector('.msg-lb-trigger-menu');
        if (!trig) {
          trig = document.createElement('div');
          trig.className = 'msg-lb-trigger-menu';
          trig.dataset.action = 'inject-click';
          trig.dataset.messageId = msg.id;
          trig.innerHTML = ICON.lbTrigger;
          nameEl.appendChild(trig);
        }
      }
    }

    if (hasMemoryStatus) {
      const nameEl = sectionEl.querySelector('.msg-name');
      if (nameEl) {
        let badge = nameEl.querySelector('.msg-memory-badge');
        if (!badge) {
          badge = document.createElement('button');
          badge.type = 'button';
          badge.className = 'msg-memory-badge';
          badge.dataset.action = 'memory-click';
          badge.dataset.messageId = msg.id;
          nameEl.appendChild(badge);
        }
        const cls = this._memoryStatusClass(msg.memoryStatus);
        badge.className = `msg-memory-badge ${cls}`;
        badge.textContent = msg.memoryStatus;
      }
    }

    if (msg.isHidden !== undefined) {
      const nameEl = sectionEl.querySelector('.msg-name');
      if (nameEl) {
        let hi = nameEl.querySelector('.msg-name-badge[data-action="toggle-hidden"]');
        if (msg.isHidden) {
          if (!hi) {
            hi = document.createElement('div');
            hi.className = 'msg-name-badge';
            hi.innerHTML = ICON.hidden;
            hi.firstChild.classList.add('msg-hidden-badge');
            hi.dataset.action = 'toggle-hidden';
            hi.dataset.messageId = msg.id;
            nameEl.appendChild(hi);
          }
        } else {
          if (hi) hi.remove();
        }
      }
    }
  }

  /* ----- Helpers ----- */
  _roleKey(role) {
    if (role === 'user') return 'user';
    if (role === 'system') return 'system';
    return 'char';
  }
  _isUser(role) { return role === 'user'; }

  _currentLayout() {
    const c = document.getElementById('chat-container');
    if (!c) return 'default';
    for (const cls of c.classList) {
      if (cls.startsWith('layout-')) return cls.slice(7);
    }
    return 'default';
  }

  _memoryStatusClass(status) {
    const s = (status || '').toLowerCase();
    if (s === 'mem')     return 'covered';
    if (s === 'pending') return 'pending';
    if (s === 'draft')   return 'draft-memory';
    if (s === 'stale')   return 'stale';
    if (s === 'rebuild') return 'needs-rebuild';
    return 'covered';
  }

  _getDefaultName(role) {
    if (role === 'user')   return 'You';
    if (role === 'system') return 'System';
    return 'Character';
  }

  _formatTime(timestamp) {
    if (!timestamp) return '';
    const d = new Date(timestamp);
    const hh = String(d.getHours()).padStart(2, '0');
    const mm = String(d.getMinutes()).padStart(2, '0');
    return `${hh}:${mm}`;
  }

  _formatDate(timestamp) {
    if (!timestamp) return null;
    const d = new Date(timestamp);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  _formatDateDisplay(dateStr) {
    const date = new Date(dateStr + 'T00:00:00');
    const today = new Date();
    const yesterday = new Date(today); yesterday.setDate(yesterday.getDate() - 1);
    if (date.toDateString() === today.toDateString())     return 'Today';
    if (date.toDateString() === yesterday.toDateString()) return 'Yesterday';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return `${months[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}`;
  }

  _createDateSeparator(dateStr) {
    const el = document.createElement('div');
    el.className = 'date-separator';
    el.dataset.dateSeparator = dateStr;
    el.innerHTML = `<div class="date-separator-line"></div><span class="date-separator-label">${this._formatDateDisplay(dateStr)}</span><div class="date-separator-line"></div>`;
    return el;
  }

  resetDateTracking() { this._lastTimestamps = { date: null, idx: -1 }; }

  _applySearchHighlight(html, globalState) {
    if (!this.searchQuery) return html;
    const escapedQuery = this.searchQuery.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(`(${escapedQuery})(?![^<]*>)`, 'gi');
    return html.replace(regex, (match) => {
      let isActive = false;
      if (globalState) {
        isActive = globalState.matchIndex === this.activeSearchIndex;
        this.searchMatches.push(globalState.matchIndex);
        globalState.matchIndex++;
      }
      return `<span class="search-highlight-text${isActive ? ' active-search-match' : ''}">${match}</span>`;
    });
  }

  setSearch(query, activeIndex = -1) {
    this.searchQuery = query;
    this.activeSearchIndex = activeIndex;
    this.searchMatches = [];
    const globalState = { matchIndex: 0 };
    
    const items = (window.bridge && window.bridge.virtualList) 
      ? window.bridge.virtualList.items.map(it => it.el) 
      : document.querySelectorAll('.message-section');
      
    let activeMessageId = null;

    items.forEach(section => {
      const isUser = section.classList.contains('user');
      
      const processHost = (host, rawText) => {
        if (host && host.shadowRoot) {
          const root = host.shadowRoot.querySelector('.glaze-message');
          if (root) {
            const formatted = this.formatter.format(rawText, isUser);
            const prevMatchIndex = globalState.matchIndex;
            root.innerHTML = this._applySearchHighlight(formatted, globalState);
            
            if (activeIndex >= prevMatchIndex && activeIndex < globalState.matchIndex) {
              activeMessageId = section.dataset.messageId || section.dataset.vlId;
            }
          }
        }
      };

      const reasoningHost = section.querySelector('.msg-reasoning-inner .message-content');
      if (reasoningHost) {
        processHost(reasoningHost, section.dataset.reasoning || '');
      }

      const bodyHost = section.querySelector('.msg-body .message-content');
      if (bodyHost) {
        processHost(bodyHost, section.dataset.rawText || '');
      }
    });

    if (activeMessageId && window.bridge) {
      window.bridge.scrollToMessage(activeMessageId);
      setTimeout(() => this._scrollToActiveMatch(), 150);
    } else {
      this._scrollToActiveMatch();
    }
  }

  _scrollToActiveMatch() {
    document.querySelectorAll('.message-content').forEach(host => {
      if (host.shadowRoot) {
        const active = host.shadowRoot.querySelector('.search-highlight-text.active-search-match');
        if (active) active.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    });
  }

  scrollToSearchMatch(index) { this.setSearch(this.searchQuery, index); }
}
