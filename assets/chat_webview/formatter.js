class Formatter {
  constructor() {
    this.cache = new Map();
    this.cacheMaxSize = 500;
  }

  format(text, isUser = false) {
    const key = `${text}:${isUser}`;

    if (this.cache.has(key)) {
      return this.cache.get(key);
    }

    let result = this._processText(text, isUser);

    // Cache management
    if (this.cache.size >= this.cacheMaxSize) {
      const firstKey = this.cache.keys().next().value;
      this.cache.delete(firstKey);
    }

    this.cache.set(key, result);
    return result;
  }

  _processText(text, isUser) {
    if (!text) return '';

    // Normalize line endings
    text = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');

    // Escape HTML
    text = this._escapeHtml(text);

    // Process code blocks first (protect from other processing)
    const codeBlocks = [];
    text = text.replace(/```(\w*)\n([\s\S]*?)```/g, (match, lang, code) => {
      const id = `__CODE_BLOCK_${codeBlocks.length}__`;
      codeBlocks.push({ lang, code });
      return id;
    });

    // Process inline code
    text = text.replace(/`([^`]+)`/g, '<code>$1</code>');

    // Process bold
    text = text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

    // Process italic
    text = text.replace(/\*([^*]+)\*/g, '<em class="chat-italic">$1</em>');

    // Process strikethrough
    text = text.replace(/~~([^~]+)~~/g, '<del>$1</del>');

    // Process links
    text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');

    // Process images
    text = text.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" loading="lazy">');

    // Process blockquotes (lines starting with >)
    text = text.replace(/^>\s?(.+)$/gm, '<blockquote>$1</blockquote>');

    // Process horizontal rules
    text = text.replace(/^(-{3,}|\*{3,}|_{3,})$/gm, '<hr>');

    // Process unordered lists
    text = this._processUnorderedList(text);

    // Process ordered lists
    text = this._processOrderedList(text);

    // Restore code blocks
    text = text.replace(/__CODE_BLOCK_(\d+)__/g, (match, index) => {
      const block = codeBlocks[parseInt(index)];
      const langAttr = block.lang ? ` class="language-${block.lang}"` : '';
      return `<pre><code${langAttr}>${block.code}</code></pre>`;
    });

    // Process quotes with special marker ==mark==...==
    text = this._processQuotes(text);

    // Process line breaks
    // Single newline -> <br>, multiple newlines -> paragraph breaks
    text = this._processLineBreaks(text);

    return text;
  }

  _escapeHtml(text) {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  _processUnorderedList(text) {
    const lines = text.split('\n');
    let result = [];
    let inList = false;
    let listItems = [];

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const match = line.match(/^(\s*)[-*+]\s+(.+)$/);

      if (match) {
        if (!inList) {
          inList = true;
          listItems = [];
        }
        listItems.push(match[2]);
      } else {
        if (inList) {
          result.push('<ul>');
          listItems.forEach(item => result.push(`<li>${item}</li>`));
          result.push('</ul>');
          inList = false;
          listItems = [];
        }
        result.push(line);
      }
    }

    if (inList) {
      result.push('<ul>');
      listItems.forEach(item => result.push(`<li>${item}</li>`));
      result.push('</ul>');
    }

    return result.join('\n');
  }

  _processOrderedList(text) {
    const lines = text.split('\n');
    let result = [];
    let inList = false;
    let listItems = [];

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const match = line.match(/^(\s*)(\d+)\.\s+(.+)$/);

      if (match) {
        if (!inList) {
          inList = true;
          listItems = [];
        }
        listItems.push(match[3]);
      } else {
        if (inList) {
          result.push('<ol>');
          listItems.forEach(item => result.push(`<li>${item}</li>`));
          result.push('</ol>');
          inList = false;
          listItems = [];
        }
        result.push(line);
      }
    }

    if (inList) {
      result.push('<ol>');
      listItems.forEach(item => result.push(`<li>${item}</li>`));
      result.push('</ol>');
    }

    return result.join('\n');
  }

  _processQuotes(text) {
    // Process ==mark==...== quotes
    text = text.replace(/==mark==([\s\S]*?)==/g, (match, content) => {
      return `<span class="chat-quote">${content}</span>`;
    });

    // Process regular quotes "..."
    text = text.replace(/"([^"]+)"/g, (match, content) => {
      return `<span class="chat-quote">"${content}"</span>`;
    });

    return text;
  }

  _processLineBreaks(text) {
    // Split into paragraphs by double newlines
    const paragraphs = text.split(/\n\s*\n/);

    return paragraphs.map(para => {
      para = para.trim();

      // Don't wrap if it's already a block element
      if (para.match(/^<(ul|ol|li|blockquote|pre|hr|div|h[1-6])/i)) {
        return para;
      }

      // Single newlines become <br>
      para = para.replace(/\n/g, '<br>');

      return `<p>${para}</p>`;
    }).join('\n');
  }
}
