/* Extracted from ../bridge.legacy.js. Keep public behavior stable. */

export class EditController {
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
    textarea.rows = 1;
    textarea.value = editText;
    textarea.dataset.originalText = editText;
    body.appendChild(textarea);

    // Modern Chromium (123+) sizes textareas to content via `field-sizing: content`.
    // Old WebViews don't — fall back to JS-driven auto-grow on input.
    const supportsFieldSizing = typeof CSS !== 'undefined'
      && CSS.supports && CSS.supports('field-sizing', 'content');
    if (!supportsFieldSizing) {
      const autoGrow = () => {
        textarea.style.height = 'auto';
        textarea.style.height = textarea.scrollHeight + 'px';
      };
      textarea.addEventListener('input', autoGrow);
      autoGrow();
    }

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
