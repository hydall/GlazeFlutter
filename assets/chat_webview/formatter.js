class Formatter {
  constructor() {
    this.cache = new Map();
    this.cacheMaxSize = 500;
  }

  format(text, isUser = false) {
    const key = `${text}:${isUser}`;
    if (this.cache.has(key)) return this.cache.get(key);

    let result;
    try {
      result = this._processText(text, isUser);
    } catch (e) {
      console.error('Formatter error:', e);
      result = (text || '').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>');
    }

    if (this.cache.size >= this.cacheMaxSize) {
      const firstKey = this.cache.keys().next().value;
      this.cache.delete(firstKey);
    }
    this.cache.set(key, result);
    return result;
  }

  _ph(prefix, i, isBlock) {
    return `\x01${prefix}${isBlock ? 'BLOCK_' : ''}${i}\x01`;
  }

  _processText(text, isUser) {
    if (!text) return '';
    text = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim();

    let html = text;

    // 1. Extract Code Blocks
    const codeBlocks = [];
    html = html.replace(/```(\w*)\n?([\s\S]*?)(?:```|$)/g, (match, lang, code) => {
      const id = this._ph('CB_', codeBlocks.length);
      codeBlocks.push({ lang, code });
      return id;
    });

    // 2. Extract HTML Tags — distinguish block vs inline
    const tagBlocks = [];
    const blockTags = new Set(['div','p','style','pre','table','ul','ol','li','h1','h2','h3','h4','h5','h6','blockquote','section','article','header','footer','hr','details','summary','figure','figcaption','svg','path','math','canvas','video','audio','form','fieldset','nav','aside','main']);
    const TAG_REGEX = /<(?:[^"'>]|"[^"]*"|'[^']*')*?>/g;

    html = html.replace(TAG_REGEX, (match) => {
      const tagMatch = match.match(/^<\/?(\w+)/);
      const isBlock = tagMatch ? blockTags.has(tagMatch[1].toLowerCase()) : false;
      const id = this._ph('T_', tagBlocks.length, isBlock);
      tagBlocks.push(match);
      return id;
    });

    // 3. Extract Glaze custom markers BEFORE quotes
    //    This protects styled segments from quote highlighting
    const styledSegments = [];
    const styledRegex = /(==hc:#[0-9a-fA-F]{3,8}==.+?==|==glow:#[0-9a-fA-F]{3,8},\d+==.+?==|==cg:#[0-9a-fA-F]{3,8},#[0-9a-fA-F]{3,8},\d+==.+?==|==grad:#[0-9a-fA-F]{3,8}(?:,#[0-9a-fA-F]{3,8})+==.+?==|==bg:#[0-9a-fA-F]{3,8}==.+?==|==mark==.+?==|==active==.+?==|\*\*[^*]+?\*\*|(?<!\*)\*[^*]+?\*(?!\*)|__[^_]+?__|(?<!\w)_[^_]+?_(?!\w)|~~[^~]+?~~)/gs;

    html = html.replace(styledRegex, (match) => {
      const id = this._ph('S_', styledSegments.length);
      styledSegments.push(match);
      return id;
    });

    // 4. Quote formatting — skip \x01 placeholders and = prefixed "..." (HTML attributes)
    const phGroup = '\x01[A-Z_]+\\d+\x01';
    const quoteRegex = new RegExp(`(${phGroup})|(=[ \\t]*"(?:[^"]|\\\\")*?")|("((?:[^"]|\\\\")*?)"|«((?:[^»])*?)»)`, 'g');
    html = html.replace(quoteRegex, (match, placeholder, skipQuote) => {
      if (placeholder) return placeholder;
      if (skipQuote) return skipQuote;
      return `<span class="chat-quote">${match}</span>`;
    });

    // 5. Restore styled segments with Glaze marker rendering
    html = html.replace(/\x01S_(\d+)\x01/g, (_, i) => {
      const seg = styledSegments[parseInt(i)];
      return this._renderStyledSegment(seg);
    });

    // 6. Markdown Parsing
    html = html.replace(/^>\s?(.*)$/gm, '<blockquote class="chat-blockquote">$1</blockquote>');
    html = html.replace(/<\/blockquote>\n*<blockquote class="chat-blockquote">/g, '<br>');
    html = html.replace(/^(_{3,}|-{3,}|\*{3,})$/gm, '<hr>');
    html = html.replace(/~~([\s\S]+?)~~/g, '<del>$1</del>');
    html = html.replace(/\*\*\*([\s\S]+?)\*\*\*/g, '<strong><em>$1</em></strong>');
    html = html.replace(/\*\*([\s\S]+?)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/\*([\s\S]+?)\*/g, '<em>$1</em>');
    html = html.replace(/<em>/g, '<em class="chat-italic">');

    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');

    // 7. Paragraphs — isolate block placeholders, don't wrap in <p>
    const blockPh = '\x01T_BLOCK_\\d+\x01';
    const codePh = '\x01CB_\\d+\x01';
    html = html.replace(new RegExp(`\\n?(${codePh}|${blockPh})\\n?`, 'g'), '\n\n$1\n\n');

    const paragraphs = html.split(/\n\n+/);
    html = paragraphs
      .map(p => {
        let trimmed = p.trim();
        if (!trimmed) return '';

        if (new RegExp(`^(${codePh}|${blockPh})$`).test(trimmed)) return trimmed;

        const startsWithBlock = new RegExp(`^${blockPh}`).test(trimmed);
        trimmed = trimmed.replace(new RegExp(`(\x01T_(?:BLOCK_)?\\d+\x01)\\s*\\n\\s*`, 'g'), '$1 ');
        trimmed = trimmed.replace(new RegExp(`\\s*\\n\\s*(\x01T_(?:BLOCK_)?\\d+\x01)`, 'g'), ' $1');
        trimmed = trimmed.replace(/\n/g, '<br>');
        return startsWithBlock ? trimmed : `<p>${trimmed}</p>`;
      })
      .filter(p => p !== '')
      .join('');

    // 8. Restore HTML Tags
    html = html.replace(/\x01T_(?:BLOCK_)?(\d+)\x01/g, (_, i) => tagBlocks[parseInt(i)]);

    // 9. Restore Code Blocks
    html = html.replace(/\x01CB_(\d+)\x01/g, (_, i) => {
      const block = codeBlocks[parseInt(i)];
      const escapedCode = block.code
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
      const langAttr = block.lang ? ` class="language-${block.lang}"` : '';
      return `<pre><code${langAttr}>${escapedCode}</code></pre>`;
    });

    return html;
  }

  _renderStyledSegment(seg) {
    // ==hc:#hex==text== — colored text
    let m = seg.match(/^==hc:(#[0-9a-fA-F]{3,8})==(.+?)==$/s);
    if (m) return `<span class="glaze-hc" style="color:${m[1]}">${m[2]}</span>`;

    // ==glow:#hex,blur==text== — glow shadow
    m = seg.match(/^==glow:(#[0-9a-fA-F]{3,8}),(\d+)==(.+?)==$/s);
    if (m) return `<span class="glaze-glow" style="text-shadow:${m[1]} 0 0 ${m[2]}px, ${m[1]} 0 0 ${parseInt(m[2])/2}px">${m[3]}</span>`;

    // ==cg:#textHex,#glowHex,blur==text== — colored + glow
    m = seg.match(/^==cg:(#[0-9a-fA-F]{3,8}),([0-9a-fA-F]{3,8}),(\d+)==(.+?)==$/s);
    if (m) {
      return `<span class="glaze-cg" style="color:${m[1]};text-shadow:${m[2]} 0 0 ${m[3]}px, ${m[2]} 0 0 ${parseInt(m[3])/2}px">${m[4]}</span>`;
    }

    // ==grad:#hex1,#hex2==text== — gradient text
    m = seg.match(/^==grad:(#[0-9a-fA-F]{3,8}(?:,#[0-9a-fA-F]{3,8})+)==(.+?)==$/s);
    if (m) {
      const colors = m[1].match(/#[0-9a-fA-F]{3,8}/g);
      const gradient = colors.join(',');
      return `<span class="glaze-grad" style="background:linear-gradient(90deg,${gradient});-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent">${m[2]}</span>`;
    }

    // ==bg:#hex==text== — background highlight
    m = seg.match(/^==bg:(#[0-9a-fA-F]{3,8})==(.+?)==$/s);
    if (m) return `<span class="glaze-bg" style="background:${m[1]};padding:1px 4px;border-radius:3px">${m[2]}</span>`;

    // ==mark==text== — quote highlight
    m = seg.match(/^==mark==(.+?)==$/s);
    if (m) return `<span class="glaze-mark">${m[1]}</span>`;

    // ==active==text== — active search match
    m = seg.match(/^==active==(.+?)==$/s);
    if (m) return `<span class="glaze-active">${m[1]}</span>`;

    // Markdown bold/italic/strikethrough (extracted to protect from quote highlighting)
    m = seg.match(/^\*\*\*(.+?)\*\*\*$/s);
    if (m) return `<strong><em>${m[1]}</em></strong>`;
    m = seg.match(/^\*\*(.+?)\*\*$/s);
    if (m) return `<strong>${m[1]}</strong>`;
    m = seg.match(/^\*(.+?)\*$/s);
    if (m) return `<em class="chat-italic">${m[1]}</em>`;
    m = seg.match(/^__(.+?)__$/s);
    if (m) return `<strong>${m[1]}</strong>`;
    m = seg.match(/^_(.+?)_$/s);
    if (m) return `<em class="chat-italic">${m[1]}</em>`;
    m = seg.match(/^~~(.+?)~~$/s);
    if (m) return `<del>${m[1]}</del>`;

    return seg;
  }
}