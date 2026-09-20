/* Article body extraction and formatting. Runs only in the local reader shell.
   Remote markup is parsed inertly, then copied through an element/attribute allowlist. */
(function (global) {
  'use strict';
  const text = v => typeof v === 'string' ? v : '';
  const escape = s => text(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const norm = s => text(s).replace(/\s+/g, ' ').trim();
  function url(value, base) {
    try { const u = new URL(value, base); return /^https?:$/.test(u.protocol) ? u.href : ''; } catch (_) { return ''; }
  }
  function markdown(value) {
    value = text(value).replace(/\r\n?/g, '\n');
    if (/^Title:/i.test(value) && /\nURL Source:/i.test(value)) value = value.replace(/^[\s\S]*?\nMarkdown Content:\s*\n/i, '');
    return global.marked.parse(value, { gfm: true, breaks: false });
  }
  const allowed = new Set('p div span h1 h2 h3 h4 h5 h6 strong b em i u s del strike mark sub sup code pre blockquote ul ol li dl dt dd table thead tbody tfoot tr th td caption figure figcaption img a br hr details summary small'.split(' '));
  const discard = new Set('script style noscript template svg canvas nav footer aside form button input select textarea iframe object embed link meta head'.split(' '));
  function sanitize(node, destination, base) {
    for (const child of Array.from(node.childNodes)) {
      if (child.nodeType === 3) { destination.appendChild(document.createTextNode(child.textContent)); continue; }
      if (child.nodeType !== 1) continue;
      const tag = child.tagName.toLowerCase();
      if (discard.has(tag) || child.hidden || child.getAttribute('aria-hidden') === 'true' || /^(none)$/i.test(child.style.display)) continue;
      if (!allowed.has(tag)) { sanitize(child, destination, base); continue; }
      const clean = document.createElement(tag);
      if (tag === 'a') {
        const href = child.getAttribute('href') || '';
        const resolved = href.startsWith('#') ? href : url(href, base);
        if (resolved) clean.setAttribute('href', resolved);
      }
      if (tag === 'img') {
        let src = child.getAttribute('src') || child.getAttribute('data-src') || '';
        if (!src || src.startsWith('data:')) src = child.getAttribute('data-src') || (child.getAttribute('srcset') || '').split(',').pop().trim().split(/\s+/)[0];
        src = url(src, base);
        if (!src) continue;
        clean.src = src; clean.alt = child.getAttribute('alt') || ''; clean.referrerPolicy = 'no-referrer';
      }
      for (const attr of ['id', 'start', 'value', 'colspan', 'rowspan']) {
        const v = child.getAttribute(attr);
        if (v && (attr === 'id' || /^\d{1,4}$/.test(v))) clean.setAttribute(attr, v);
      }
      if (tag === 'details') clean.open = true;
      // Keep author emphasis and alignment without importing page layout or scripts.
      for (const property of ['fontWeight', 'fontStyle', 'textDecoration', 'textAlign', 'verticalAlign', 'color', 'backgroundColor']) {
        if (child.style[property]) clean.style[property] = child.style[property];
      }
      sanitize(child, clean, base);
      destination.appendChild(clean);
    }
  }
  function cleanHTML(html, base, fullPage) {
    const parsed = new DOMParser().parseFromString(html, 'text/html');
    let root = parsed.body;
    if (fullPage) {
      // Prefer a body-specific element over a teaser <article> or the page chrome.
      root = parsed.querySelector('[itemprop="articleBody"],.e-content,.entry-content,.post-content,article.content') ||
        Array.from(parsed.querySelectorAll('article')).sort((a, b) => b.textContent.length - a.textContent.length)[0] ||
        parsed.querySelector('main') || parsed.body;
    }
    const result = document.createElement('div');
    sanitize(root, result, base);
    return result;
  }
  function facetsHTML(value) {
    const valueText = text(value.text) || text(value.plainText);
    const bytes = new TextEncoder().encode(valueText);
    const facets = (Array.isArray(value.facets) ? value.facets : []).filter(f => f && f.index &&
      Number.isInteger(f.index.byteStart) && Number.isInteger(f.index.byteEnd) && f.index.byteStart >= 0 && f.index.byteEnd <= bytes.length && f.index.byteEnd > f.index.byteStart);
    const cuts = Array.from(new Set([0, bytes.length, ...facets.flatMap(f => [f.index.byteStart, f.index.byteEnd])])).sort((a, b) => a - b);
    let result = '';
    for (let i = 0; i + 1 < cuts.length; i++) {
      let piece = escape(new TextDecoder().decode(bytes.slice(cuts[i], cuts[i + 1])));
      for (const facet of facets.filter(f => f.index.byteStart <= cuts[i] && f.index.byteEnd >= cuts[i + 1])) {
        for (const feature of facet.features || []) {
          const type = text(feature.$type).split('#').pop().toLowerCase();
          const tag = { bold: 'strong', italic: 'em', underline: 'u', strikethrough: 'del', code: 'code', highlight: 'mark' }[type];
          if (tag) piece = `<${tag}>${piece}</${tag}>`;
          if (type === 'link') piece = `<a href="${escape(text(feature.uri) || text(feature.href))}">${piece}</a>`;
        }
      }
      result += piece;
    }
    return result;
  }
  function imageURL(value, article, depth = 0) {
    if (depth > 12 || !value) return '';
    if (typeof value === 'string') return url(value, article.url);
    for (const key of ['url', 'src', 'fullsize', 'thumbnail', 'image', 'blob', 'file']) {
      if (value[key]) { const found = imageURL(value[key], article, depth + 1); if (found) return found; }
    }
    const cid = text(value.$link) || text(value.ref && value.ref.$link);
    const did = text(article.documentURI).split('/')[2];
    return cid && did ? `https://cdn.bsky.app/img/feed_fullsize/plain/${encodeURIComponent(did)}/${encodeURIComponent(cid)}@jpeg` : '';
  }
  function structured(value, article, depth = 0) {
    if (depth > 64 || value == null) return '';
    if (Array.isArray(value)) return value.map(v => structured(v, article, depth + 1)).join('');
    if (typeof value === 'string') return markdown(value);
    const type = (text(value.$type) || text(value.type)).toLowerCase();
    if (value.html || /html/.test(type)) return text(value.html) || text(value.text) || text(value.content);
    if (value.markdown || /markdown/.test(type)) return markdown(text(value.markdown) || text(value.text) || text(value.content));
    if (value.block) {
      const alignment = /textAlign(Left|Center|Right|Justify)/.exec(text(value.alignment));
      return `<div${alignment ? ` style="text-align:${alignment[1].toLowerCase()}"` : ''}>${structured(value.block, article, depth + 1)}</div>`;
    }
    const kids = () => ['pages', 'blocks', 'block', 'children', 'content', 'root'].filter(k => value[k] && typeof value[k] !== 'string').map(k => structured(value[k], article, depth + 1)).join('');
    let inline = facetsHTML(value);
    if (!inline && typeof value.content === 'string') inline = escape(value.content);
    if (!inline && typeof value.value === 'string') inline = escape(value.value);
    if (/image/.test(type)) return `<figure><img src="${escape(imageURL(value, article))}" alt="${escape(text(value.alt))}">${value.caption ? `<figcaption>${escape(text(value.caption))}</figcaption>` : ''}</figure>`;
    if (/horizontalrule|thematicbreak/.test(type)) return '<hr>';
    if (/list/.test(type) && !/listitem/.test(type) && Array.isArray(value.items || value.children || value.content)) {
      const tag = /ordered/.test(type) && !/unordered/.test(type) ? 'ol' : 'ul';
      const listItems = items => items.map(v => {
        const checked = typeof v.checked === 'boolean' ? (v.checked ? '☑ ' : '☐ ') : '';
        const nested = Array.isArray(v.children) ? `<${tag}>${listItems(v.children)}</${tag}>` : structured(v.orderedListChildren || v.unorderedListChildren, article, depth + 1);
        return `<li>${checked}${structured(v.content || v, article, depth + 1)}${nested}</li>`;
      }).join('');
      return `<${tag} start="${Number(value.startIndex) || 1}">${listItems(value.items || value.children || value.content)}</${tag}>`;
    }
    const notes = (value.facets || []).flatMap(f => f.features || []).filter(f => text(f.$type).endsWith('#footnote'));
    const noteHTML = notes.map(f => `<p><sup>${escape(text(f.footnoteId))}</sup> ${facetsHTML({ text: f.contentPlaintext, facets: f.contentFacets })}</p>`).join('');
    const inner = inline + kids() + noteHTML;
    if (/heading|header/.test(type) && !/table/.test(type)) return `<h${Math.min(6, Math.max(1, Number(value.level || value.attrs?.level) || 2))}>${inner}</h${Math.min(6, Math.max(1, Number(value.level || value.attrs?.level) || 2))}>`;
    if (/blockquote|quote/.test(type)) return `<blockquote>${inner}</blockquote>`;
    if (/codeblock|\.code($|#)|#code$/.test(type)) return `<pre><code>${escape(text(value.code) || text(value.text)) || kids()}</code></pre>`;
    if (type === 'text') {
      let marked = inline;
      for (const mark of value.marks || []) {
        const tag = { bold: 'strong', strong: 'strong', italic: 'em', em: 'em', code: 'code', strike: 'del', underline: 'u' }[mark.type];
        if (tag) marked = `<${tag}>${marked}</${tag}>`;
        if (mark.type === 'link') marked = `<a href="${escape(mark.attrs?.href)}">${marked}</a>`;
      }
      if (Number.isInteger(value.format)) {
        for (const [bit, tag] of [[1,'strong'],[2,'em'],[4,'del'],[8,'u'],[16,'code'],[32,'sub'],[64,'sup'],[128,'mark']]) {
          if (value.format & bit) marked = `<${tag}>${marked}</${tag}>`;
        }
      }
      return marked;
    }
    if (/hardbreak/.test(type)) return '<br>';
    if (/paragraph|\.text($|#)|#text$/.test(type)) return `<p>${inner}</p>`;
    if (/tablecell|tableheader/.test(type)) return `<${type.includes('header') ? 'th' : 'td'}>${inner}</${type.includes('header') ? 'th' : 'td'}>`;
    if (/tablerow/.test(type)) return `<tr>${inner}</tr>`;
    if (/table/.test(type)) return `<table>${inner}</table>`;
    return inner || (value.text ? `<p>${inline}</p>` : '');
  }
  function normalizeBody(node, title) {
    const heading = node.querySelector('h1,h2');
    if (heading && norm(heading.textContent) === norm(title) && !norm(node.textContent.slice(0, node.textContent.indexOf(heading.textContent)))) heading.remove();
    return node;
  }
  function bodyText(node) {
    const copy = node.cloneNode(true);
    copy.querySelectorAll('p,div,h1,h2,h3,h4,h5,h6,li,blockquote,pre,tr,td,th,br,figcaption').forEach(el => el.appendChild(document.createTextNode(' ')));
    return norm(copy.textContent);
  }
  function complete(candidate, fallback) {
    const blocks = Array.from(fallback.children);
    // Preserve paragraphs absent from a partial/unsupported rich document. Insert
    // relative to the next known paragraph, so a missing middle section stays there.
    for (let i = 0; i < blocks.length; i++) {
      const content = bodyText(blocks[i]);
      if (!content || bodyText(candidate).includes(content)) continue;
      let next = null;
      for (let j = i + 1; j < blocks.length && !next; j++) {
        const target = bodyText(blocks[j]);
        if (target) next = Array.from(candidate.children).find(el => bodyText(el).includes(target));
      }
      candidate.insertBefore(blocks[i].cloneNode(true), next);
    }
    return candidate;
  }
  function render(article, canonical) {
    const base = article.url;
    const fallback = normalizeBody(cleanHTML(markdown(article.rawTextContent || article.textContent || ''), base, false), article.title);
    const rich = normalizeBody(cleanHTML(structured(article.content, article), base, false), article.title);
    let result = norm(rich.textContent) || rich.querySelector('img') ? complete(rich, fallback) : fallback;
    let usable = false;
    if (canonical) {
      const isHTML = /<(?:!doctype|html|body|article|main|p|div|h[1-6])(?:\s|>)/i.test(canonical);
      const page = normalizeBody(cleanHTML(isHTML ? canonical : markdown(canonical), base, isHTML), article.title);
      const pageText = bodyText(page);
      const expected = bodyText(result);
      // Reject an error/challenge page and a short teaser replacing the article.
      const expectedWords = new Set(expected.toLowerCase().split(/\s+/).filter(v => v.length > 3));
      const pageWords = new Set(pageText.toLowerCase().split(/\s+/));
      const overlap = expectedWords.size ? [...expectedWords].filter(v => pageWords.has(v)).length / expectedWords.size : 1;
      usable = pageText.length > 0 && !/^(access denied|just a moment|checking your browser|403 forbidden|404 not found)/i.test(pageText) &&
        (expectedWords.size < 10 || overlap > 0.65);
      if (usable) result = complete(page, result);
    }
    return { html: result.innerHTML, text: bodyText(result), usable };
  }
  global.NFBArticle = { render, cleanHTML, facetsHTML };
  if (typeof module !== 'undefined') module.exports = global.NFBArticle;
})(typeof window !== 'undefined' ? window : globalThis);
