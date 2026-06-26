import { ICON } from './icon_library.js';
import { createImageAttachment } from './image_embed.js';
import { writeShadowContent } from './markdown.js';
import {
  defaultName,
  formatDate,
  formatDateDisplay,
  formatTime,
  isUserRole,
  memoryStatusClass,
  roleKey,
} from './message_template.js';
import { SHADOW_STYLE } from './shadow_style.js';

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

export class Renderer {
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
    if (messageData.messageIndex == null && this.virtualList) {
      const items = this.virtualList.items;
      for (let i = items.length - 1; i >= 0; i--) {
        const el = items[i].el;
        if (el && el.dataset && el.dataset.messageIndex != null) {
          messageData.messageIndex = parseInt(el.dataset.messageIndex, 10) + 1;
          break;
        }
      }
    }

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
      id, role, text, reasoning, studioOutputs, studioOutputsExpanded,
      isError, isHidden, isLast, isTyping,
      guidanceText, guidanceType,
      imagePath, imageHidden,
    } = messageData;

    const layout = this._currentLayout();

    const section = document.createElement('div');
    section.dataset.messageId = id;
    section.dataset.rawText = text || '';
    if (reasoning) section.dataset.reasoning = reasoning;
    if (studioOutputs && studioOutputs.length) section.dataset.studioOutputs = JSON.stringify(studioOutputs);
    if (isLast && this._roleKey(role) === 'char') section.dataset.isLast = 'true';
    if (messageData.personaName) section.dataset.personaName = messageData.personaName;
    if (messageData.messageIndex != null) section.dataset.messageIndex = String(messageData.messageIndex);
    if (messageData.swipeIndex != null) section.dataset.swipeId = String(messageData.swipeIndex);
    if (messageData.swipeTotal != null) section.dataset.swipeTotal = String(messageData.swipeTotal);
    if (messageData.agentSwipeIndex != null) section.dataset.agentSwipeId = String(messageData.agentSwipeIndex);
    if (messageData.agentSwipeTotal != null) section.dataset.agentSwipeTotal = String(messageData.agentSwipeTotal);
    if (messageData.greetingTotal != null) section.dataset.greetingTotal = String(messageData.greetingTotal);

    const classes = ['message-section', this._roleKey(role), `layout-${layout}`];
    if (isError) classes.push('error');
    if (isHidden) classes.push('msg-hidden');
if (messageData.isEditing) classes.push('editing');
    if (this.selectionManager) this.selectionManager.applyClassesToSection(section, classes);
    section.className = classes.join(' ');
    section.classList.add('msg-appear');
    section.addEventListener('animationend', () => section.classList.remove('msg-appear'), { once: true });

    /* --- Header --- */
    section.appendChild(this._createHeader(messageData));

    /* --- Guidance block (header-level) --- */
    if (guidanceText) {
      section.appendChild(this._createGuidanceBlock(guidanceText, guidanceType));
    }

    /* --- Content stack --- */
    const stack = document.createElement('div');
    stack.className = 'msg-content-stack';

    /* --- Reasoning (inside content stack so it flows with the bubble) --- */
    if (reasoning && reasoning.trim()) {
      stack.appendChild(this._createReasoningBlock(reasoning, this._isUser(role)));
    }
    if (studioOutputs && studioOutputs.length) {
      stack.appendChild(this._createStudioOutputsBlock(id, studioOutputs, this._isUser(role), studioOutputsExpanded));
    }

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
    const roleKey = this._roleKey(m.role);
    const finalName = m.displayName || m.personaName || this._getDefaultName(m.role);
    const identity = window.bridge || null;
    const avatarUrl = m.avatarUrl || (roleKey === 'user'
      ? (identity && identity._personaAvatarUrl)
      : roleKey === 'char'
        ? (identity && identity._charAvatarUrl)
        : null);
    if (avatarUrl) {
      const img = document.createElement('img');
      img.src = avatarUrl;
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
      (m.triggeredMemories && m.triggeredMemories.length) ||
      (m.triggeredRegexes && m.triggeredRegexes.length);
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

  _createStudioOutputsBlock(messageId, outputs, isUser, expanded = false) {
    const panel = document.createElement('div');
    panel.className = 'msg-studio-outputs';

    const title = document.createElement('div');
    title.className = 'msg-studio-title';
    title.textContent = 'Studio Agents';
    panel.appendChild(title);

    for (const output of outputs || []) {
      const item = document.createElement('div');
      item.className = expanded ? 'msg-studio-output' : 'msg-studio-output collapsed';
      if (output.status === 'error') item.classList.add('error');
      item.dataset.outputId = output.id || '';

      const header = document.createElement('div');
      header.className = 'msg-studio-output-header';
      header.dataset.action = 'toggle-studio-output';
      header.dataset.outputId = output.id || '';

      const name = document.createElement('span');
      name.className = 'msg-studio-output-name';
      name.textContent = output.status === 'error'
        ? `${output.name || 'Studio Agent'} — error`
        : output.name || 'Studio Agent';
      header.appendChild(name);

      const actions = document.createElement('span');
      actions.className = 'msg-studio-output-actions';
      const edit = document.createElement('button');
      edit.type = 'button';
      edit.className = 'msg-studio-output-edit';
      edit.dataset.action = 'studio-output-edit';
      edit.dataset.outputId = output.id || '';
      edit.dataset.messageId = messageId;
      edit.title = 'Edit Studio output';
      edit.innerHTML = ICON.edit;
      actions.appendChild(edit);
      if (output.status === 'error') {
        const regen = document.createElement('button');
        regen.type = 'button';
        regen.className = 'msg-studio-output-regen';
        regen.dataset.action = 'studio-output-regen';
        regen.dataset.outputId = output.id || '';
        regen.dataset.messageId = messageId;
        regen.title = 'Regenerate Studio output';
        regen.innerHTML = ICON.regen;
        actions.appendChild(regen);
      }
      const caret = document.createElement('span');
      caret.className = 'msg-studio-output-caret';
      caret.innerHTML = ICON.chevron;
      actions.appendChild(caret);
      header.appendChild(actions);

      const content = document.createElement('div');
      content.className = 'msg-studio-output-content';
      const wrap = document.createElement('div');
      wrap.className = 'msg-transition-wrapper';
      const inner = document.createElement('div');
      inner.className = 'msg-studio-output-inner';
      const shadowHost = this._createContentContainer();
      inner.appendChild(shadowHost);
      this._writeShadowContent(shadowHost, output.content || '', isUser, false);
      wrap.appendChild(inner);
      content.appendChild(wrap);

      item.appendChild(header);
      item.appendChild(content);
      panel.appendChild(item);
    }

    return panel;
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
    return createImageAttachment(src, hidden, ICON);
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
      const rn = new RollingNumber(genTime);
      rn.el.classList.add('gen-time');
      rn.el.classList.add('gen-time-badge');
      gw.rollingNumber = rn;
      gw.appendChild(rn.el);
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
    const hasAgentSwipes = isChar && m.agentSwipeFinalCount && m.agentSwipeFinalCount > 1;
    const hasGreetings = isChar && m.messageIndex === 0 && m.greetingTotal && m.greetingTotal > 1;
    const showRegen = ((!isChar && m.isLast) || m.isError) && !m.isGenerating && !m.isEditing;
    const showStudioFinalRegen = isChar && m.isLast && !m.isGenerating && !m.isEditing && m.studioOutputs && m.studioOutputs.length;

    if (hasSwipes) {
      center.appendChild(this._createSwitcher(m.id, m.swipeIndex || 0, m.swipeTotal, 'swipe'));
    } else if (hasGreetings) {
      center.appendChild(this._createSwitcher(m.id, m.greetingIndex || 0, m.greetingTotal, 'greeting'));
    }

    // Nested swipes: blue sub-swipe switcher (final/cleaned/regen-final).
    if (hasAgentSwipes) {
      center.appendChild(this._createSwitcher(m.id, m.agentSwipeIndex || 0, m.agentSwipeTotal, 'agent-swipe'));
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

    if (showRegen || showStudioFinalRegen) {
      const regen = document.createElement('div');
      regen.className = 'msg-regenerate';
      if (hasSwipes || hasGreetings || showStudioFinalRegen) regen.classList.add('icon-only');
      regen.dataset.action = 'regenerate';
      regen.dataset.messageId = m.id;
      regen.dataset.mode = 'magic';
      regen.title = showStudioFinalRegen ? 'Regenerate full Studio pipeline' : 'Regenerate';
      regen.innerHTML = ICON.regen;
      if (!hasSwipes && !hasGreetings && !showStudioFinalRegen) {
        const span = document.createElement('span');
        span.textContent = '↻';
        // text label; Flutter side may localize
        span.textContent = 'Regenerate';
        regen.appendChild(span);
      }
      center.appendChild(regen);

      if (showStudioFinalRegen) {
        const finalRegen = document.createElement('div');
        finalRegen.className = 'msg-regenerate studio-final-only';
        finalRegen.dataset.action = 'regenerate';
        finalRegen.dataset.messageId = m.id;
        finalRegen.dataset.mode = 'studio-final';
        finalRegen.title = 'Regenerate final Studio agent only (reuses agent briefs)';
        finalRegen.innerHTML = ICON.regen;
        const label = document.createElement('span');
        label.className = 'studio-final-only-label';
        label.textContent = 'Final';
        finalRegen.appendChild(label);
        center.appendChild(finalRegen);
      }
    }

    footer.appendChild(center);

    /* --- Right: actions / edit buttons --- */
    if (m.isEditing) {
      footer.appendChild(this._createEditButtons(m.id));
    } else if (!this.selectionManager || !this.selectionManager.shouldHideActions()) {
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
    if (kind === 'agent-swipe') wrap.classList.add('agent-switcher');

    const prev = document.createElement('div');
    prev.className = 'msg-switcher-btn prev';
    prev.dataset.action = kind === 'greeting' ? 'greeting-prev'
      : kind === 'agent-swipe' ? 'agent-swipe-left' : 'swipe-left';
    prev.dataset.messageId = messageId;
    prev.innerHTML = ICON.swipeLeft;
    wrap.appendChild(prev);

    const count = document.createElement('div');
    count.className = 'msg-switcher-count';
    count.textContent = `${index + 1}/${total}`;
    wrap.appendChild(count);

    const next = document.createElement('div');
    next.className = 'msg-switcher-btn next';
    next.dataset.action = kind === 'greeting' ? 'greeting-next'
      : kind === 'agent-swipe' ? 'agent-swipe-right' : 'swipe-right';
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
    writeShadowContent({
      host,
      text,
      isUser,
      isTyping,
      formatter: this.formatter,
      searchQuery: this.searchQuery,
      applySearchHighlight: (html) => this._applySearchHighlight(html),
    });
  }

  /* ----- Public mutation API ----- */
  updateMessageContent(sectionEl, text, reasoning, isUser, isTyping, animate, studioOutputs = null, studioOutputsExpanded = false) {
    if (!sectionEl) return;
    const body = sectionEl.querySelector('.msg-body');
    if (!body) return;

    const isError = sectionEl.classList.contains('error');

    if (!isTyping && !isError && !animate) {
      const existingHost = body.querySelector('.message-content');
      if (existingHost && existingHost.shadowRoot) {
        const glazeMsg = existingHost.shadowRoot.querySelector('.glaze-message');
        if (glazeMsg) {
          this._writeShadowContent(existingHost, text, isUser, false);
          if (reasoning && reasoning.trim()) {
            let reasoningEl = sectionEl.querySelector('.msg-reasoning');
            if (reasoningEl) {
              const rHost = reasoningEl.querySelector('.msg-reasoning-inner .message-content');
              if (rHost) this._writeShadowContent(rHost, reasoning, isUser, false);
            }
          }
          this._syncStudioOutputs(sectionEl, studioOutputs, isUser, studioOutputsExpanded);
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

    /* Reasoning lives inside .msg-content-stack (before .msg-transition-wrapper) */
    let reasoningEl = sectionEl.querySelector('.msg-reasoning');
    if (reasoning && reasoning.trim()) {
      if (!reasoningEl) {
        reasoningEl = this._createReasoningBlock(reasoning, isUser);
        const contentStack = sectionEl.querySelector('.msg-content-stack');
        contentStack.insertBefore(reasoningEl, contentStack.firstChild);
      } else {
        const host = reasoningEl.querySelector('.msg-reasoning-inner .message-content');
        if (host) this._writeShadowContent(host, reasoning, isUser, false);
      }
    } else if (reasoningEl) {
      reasoningEl.remove();
    }

    this._syncStudioOutputs(sectionEl, studioOutputs, isUser, studioOutputsExpanded);

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

  _syncStudioOutputs(sectionEl, studioOutputs, isUser, expanded = false) {
    if (studioOutputs === null) return;
    const contentStack = sectionEl.querySelector('.msg-content-stack');
    if (!contentStack) return;
    const existing = sectionEl.querySelector('.msg-studio-outputs');
    if (studioOutputs && studioOutputs.length) {
      const replacement = this._createStudioOutputsBlock(
        sectionEl.dataset.messageId,
        studioOutputs,
        isUser,
        expanded,
      );
      if (existing) existing.replaceWith(replacement);
      else {
        const reasoningEl = sectionEl.querySelector('.msg-reasoning');
        const anchor = reasoningEl ? reasoningEl.nextSibling : contentStack.firstChild;
        contentStack.insertBefore(replacement, anchor);
      }
      sectionEl.dataset.studioOutputs = JSON.stringify(studioOutputs);
    } else if (existing) {
      existing.remove();
      delete sectionEl.dataset.studioOutputs;
    }
  }

  updateMessage(messageId, newText, isUser = false, reasoning = null) {
    const el = document.querySelector(`[data-message-id="${messageId}"]`);
    if (el) {
      let studioOutputs = null;
      try { studioOutputs = el.dataset.studioOutputs ? JSON.parse(el.dataset.studioOutputs) : null; }
      catch (_) { studioOutputs = null; }
      this.updateMessageContent(el, newText, reasoning || el.dataset.reasoning || null, isUser, false, false, studioOutputs);
    }
  }

  updateMessageMeta(sectionEl, msg) {
    if (msg.messageIndex !== undefined && msg.messageIndex !== null) {
      sectionEl.dataset.messageIndex = String(msg.messageIndex);
      const idxStr = `#${msg.messageIndex + 1}`;
      
      const headerName = sectionEl.querySelector('.msg-header .msg-name');
      if (headerName) {
        let idx = headerName.querySelector('.msg-index');
        if (!idx) {
          idx = document.createElement('span');
          idx.className = 'msg-index gen-stat header-idx';
          const label = headerName.querySelector('.msg-name-label');
          if (label && label.nextSibling) {
            headerName.insertBefore(idx, label.nextSibling);
          } else {
            headerName.appendChild(idx);
          }
        }
        idx.textContent = idxStr;
      }
      
      const bubbleMeta = sectionEl.querySelector('.bubble-meta');
      if (bubbleMeta) {
        let idx = bubbleMeta.querySelector('.msg-index');
        if (!idx) {
          idx = document.createElement('span');
          idx.className = 'msg-index gen-stat';
          bubbleMeta.insertBefore(idx, bubbleMeta.firstChild);
        }
        idx.textContent = idxStr;
      }
    }

    const hasGen = msg.genTime && msg.genTime !== '0s';
    const hasTokens = msg.tokens && msg.tokens > 0 && !msg.isTyping;
    const hasTrigger = (msg.triggeredLorebooks && msg.triggeredLorebooks.length) ||
                       (msg.triggeredMemories && msg.triggeredMemories.length) ||
                       (msg.triggeredRegexes && msg.triggeredRegexes.length);
    const hasMemoryStatus = !!msg.memoryStatus;

    let bubbleMeta = sectionEl.querySelector('.bubble-meta');
    let footerMeta = sectionEl.querySelector('.msg-meta');

    if (hasGen || hasTokens) {
      let genStatBubble = bubbleMeta?.querySelector('.gen-stat');
      let genStatFooter = footerMeta?.querySelector('.gen-stat');

      if (hasGen) {
        const timeStr = msg.genTime;
        if (genStatBubble) {
          const wrapper = genStatBubble.querySelector('.gen-time-wrapper');
          if (wrapper && wrapper.rollingNumber) {
            wrapper.rollingNumber.setValue(timeStr);
          } else {
            const badge = genStatBubble.querySelector('.gen-time-badge');
            if (badge) badge.textContent = timeStr;
          }
        }
        if (genStatFooter) {
          const wrapper = genStatFooter.querySelector('.gen-time-wrapper');
          if (wrapper && wrapper.rollingNumber) {
            wrapper.rollingNumber.setValue(timeStr);
          } else {
            const badge = genStatFooter.querySelector('.gen-time-badge');
            if (badge) badge.textContent = timeStr;
          }
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

    if (!hasTokens) {
      // The current swipe has no token count (e.g. it is still streaming) —
      // drop any stale count left over from a sibling variation so the old
      // value isn't shown during the generation animation.
      sectionEl.querySelectorAll('.token-count-inline').forEach((el) => el.remove());
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
    } else {
      // The current swipe triggered no entries — drop any stale button left
      // over from a sibling variation that did (per-swipe triggered entries).
      sectionEl.querySelector('.msg-lb-trigger-menu')?.remove();
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
      // Place the crossed-out-eye badge to the left of the time, matching the
      // initial render (_createHeader / _createBubbleMeta).
      sectionEl.querySelectorAll('.msg-time, .bubble-time').forEach((timeEl) => {
        let hi = timeEl.querySelector('.msg-hidden-badge');
        if (msg.isHidden) {
          if (!hi) {
            const eye = document.createElement('span');
            eye.innerHTML = ICON.hidden;
            hi = eye.firstChild;
            hi.classList.add('msg-hidden-badge');
            hi.dataset.action = 'toggle-hidden';
            hi.dataset.messageId = msg.id;
            timeEl.insertBefore(hi, timeEl.firstChild);
          }
        } else if (hi) {
          hi.remove();
        }
      });
    }
  }

  /* ----- Helpers ----- */
  _roleKey(role) { return roleKey(role); }
  _isUser(role) { return isUserRole(role); }

  _currentLayout() {
    const c = document.getElementById('chat-container');
    if (!c) return 'default';
    for (const cls of c.classList) {
      if (cls.startsWith('layout-')) return cls.slice(7);
    }
    return 'default';
  }

  _memoryStatusClass(status) { return memoryStatusClass(status); }
  _getDefaultName(role) { return defaultName(role); }
  _formatTime(timestamp) { return formatTime(timestamp); }
  _formatDate(timestamp) { return formatDate(timestamp); }
  _formatDateDisplay(dateStr) { return formatDateDisplay(dateStr); }

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

  animateRemoveSection(el, onDone) {
    if (!el) { onDone?.(); return; }
    if (el.classList.contains('native-lite')) { onDone?.(); return; }
    const h = el.offsetHeight;
    el.style.overflow = 'hidden';
    el.style.pointerEvents = 'none';
    el.style.transition = 'opacity 0.18s ease, transform 0.18s ease';
    el.style.opacity = '0';
    el.style.transform = 'translateY(-8px)';
    setTimeout(() => {
      el.style.transition = 'max-height 0.14s ease, padding-top 0.14s ease, padding-bottom 0.14s ease, margin-top 0.14s ease, margin-bottom 0.14s ease';
      el.style.maxHeight = h + 'px';
      requestAnimationFrame(() => requestAnimationFrame(() => {
        el.style.maxHeight = '0';
        el.style.paddingTop = '0';
        el.style.paddingBottom = '0';
        el.style.marginTop = '0';
        el.style.marginBottom = '0';
      }));
      setTimeout(() => onDone?.(), 150);
    }, 190);
  }
}
