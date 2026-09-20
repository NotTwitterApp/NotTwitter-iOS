const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require(path.join(process.env.NFB_WEB_REFERENCE || path.resolve(__dirname, '../../../twitter-clone'), 'node_modules/jsdom'));
const dom = new JSDOM('', { runScripts: 'outside-only' });
dom.window.TextEncoder = TextEncoder; dom.window.TextDecoder = TextDecoder;
for (const file of ['nfb-marked-15.0.12.js', 'nfb-article-reader.js']) dom.window.eval(fs.readFileSync(`${__dirname}/../Resources/${file}`, 'utf8'));
const reader = dom.window.NFBArticle;
const parsed = html => new JSDOM(html).window.document;
let count = 0;
function test(name, run) { run(); count++; console.log(`PASS ${name}`); }
const base = { url: 'https://example.org/posts/story', title: 'Story' };
test('nested HTML keeps bare text, captions, table cells, lists, code and emphasis', () => {
 const result = reader.render(base, '<nav>Ignore menu</nav><article><h1>Story</h1><div>Intro <strong>bold <em>and italic</em></strong><section><p>Middle<br>line</p><ol start="3"><li>First<ul><li>Nested</li></ul></li></ol><figure><img src="/photo.jpg"><figcaption>Caption</figcaption></figure><table><tr><th>Column</th><td>Value</td></tr></table><pre><code>if (a &lt; b)\n  go();</code></pre><div>Last bare text <a href="../next">Next story</a></div></section></div></article><footer>Ignore footer</footer>');
 for (const value of ['Intro', 'Middle', 'Nested', 'Caption', 'Column', 'Value', 'Last bare text']) assert.ok(result.text.includes(value));
 const d=parsed(result.html); assert.ok(d.querySelector('strong em')); assert.equal(d.querySelector('ol').start, 3); assert.equal(d.querySelector('a').href, 'https://example.org/next'); assert.ok(d.querySelector('pre').textContent.includes('\n')); assert.ok(!result.text.includes('Ignore'));
});
test('Markdown preserves bold+italic, links, lists, fences and tables', () => {
 const r=reader.render({...base,textContent:'# Section\n\n***Both*** and ~~removed~~ [Link](/next).\n\n1. One\n2. Two\n\n| A | B |\n| - | - |\n| C | D |\n\n```js\nlet x = 1;\n```'});
 const d=parsed(r.html); assert.ok(d.querySelector('strong em,em strong')); assert.ok(d.querySelector('del')); assert.ok(d.querySelector('table')); assert.equal(d.querySelectorAll('li').length,2); assert.equal(d.querySelector('a').href,'https://example.org/next');
});
test('Leaflet wrapper blocks, ordered nested children and UTF8 overlapping facets', () => {
 const r=reader.render({...base,content:{$type:'pub.leaflet.content',pages:[{$type:'pub.leaflet.pages.linearDocument',blocks:[{block:{$type:'pub.leaflet.blocks.header',level:3,text:'Heading'}},{alignment:'#textAlignCenter',block:{$type:'pub.leaflet.blocks.text',text:'🌞 café bold',facets:[{index:{byteStart:5,byteEnd:10},features:[{$type:'pub.leaflet.richtext.facet#bold'},{$type:'pub.leaflet.richtext.facet#italic'}]}]}},{block:{$type:'pub.leaflet.blocks.orderedList',startIndex:4,children:[{content:{$type:'pub.leaflet.blocks.text',text:'Parent'},children:[{content:{$type:'pub.leaflet.blocks.text',text:'Child'}}]}]}}]}]}});
 const d=parsed(r.html); assert.equal(d.querySelector('h3').textContent,'Heading'); assert.equal(d.querySelector('em strong,strong em').textContent,'café'); assert.equal(d.querySelector('ol').start,4); assert.ok(d.querySelector('ol ol li').textContent.includes('Child')); assert.ok(d.querySelector('[style*="center"]'));
});
test('partial rich content does not discard a middle or final paragraph', () => {
 const a={...base,textContent:'First paragraph.\n\nMissing middle paragraph.\n\nFinal paragraph.',content:{$type:'custom',blocks:[{$type:'pub.leaflet.blocks.text',text:'First paragraph.'},{$type:'pub.leaflet.blocks.text',text:'Final paragraph.'}]}};
 const r=reader.render(a); assert.equal(r.text,'First paragraph. Missing middle paragraph. Final paragraph.');
});
test('complete HTML does not duplicate a flattened record body', () => {
 const r=reader.render({...base,textContent:'First paragraph. Last paragraph.'},'<article><p>First <b>paragraph.</b></p><p>Last paragraph.</p></article>');
 assert.equal(r.text,'First paragraph. Last paragraph.'); assert.equal(parsed(r.html).querySelectorAll('p').length,2);
});
test('canonical text adds content even when the record already has a heading', () => {
 const r=reader.render({...base,textContent:'Existing paragraph.',content:{type:'doc',content:[{type:'heading',attrs:{level:2},content:[{type:'text',text:'Section'}]},{type:'paragraph',content:[{type:'text',text:'Existing paragraph.'}]}]}},'<article><h2>Section</h2><p>Existing <em>paragraph.</em></p><p>Complete closing paragraph.</p></article>');
 assert.ok(r.text.includes('Complete closing paragraph.')); assert.ok(parsed(r.html).querySelector('em'));
});
test('failed/challenge HTML retains record text and safe markup blocks active content', () => {
 const r=reader.render({...base,textContent:'Keep this article.'},'<body>Access denied</body>'); assert.equal(r.usable,false); assert.equal(r.text,'Keep this article.');
 const d=reader.cleanHTML('<p onclick="bad()">Safe<script>bad()</script><a href="javascript:bad()">text</a><img src="https://example.org/x" onerror="bad()"><iframe src="https://evil.test"></iframe></p>',base.url,false);
 assert.ok(!/onclick|onerror|javascript:|<script|<iframe/.test(d.innerHTML));
});
test('latest revision replaces earlier content', () => {
 const old=reader.render({...base,textContent:'Old body.'});const latest=reader.render({...base,textContent:'Edited **new body**.'});assert.ok(old.text.includes('Old'));assert.ok(!latest.text.includes('Old'));assert.ok(parsed(latest.html).querySelector('strong'));
});
test('structured footnotes, Lexical marks, ProseMirror table and nested lists preserve formatting', () => {
 const r=reader.render({...base,content:{type:'doc',content:[{type:'paragraph',content:[{type:'text',text:'Bold italic',format:3}]},{type:'table',content:[{type:'tableRow',content:[{type:'tableHeader',content:[{type:'text',text:'Heading cell'}]},{type:'tableCell',content:[{type:'text',text:'Body cell'}]}]}]},{type:'bulletList',content:[{type:'listItem',content:[{type:'paragraph',content:[{type:'text',text:'List text'}]},{type:'bulletList',content:[{type:'listItem',content:[{type:'text',text:'Nested'}]}]}]}]},{$type:'pub.leaflet.blocks.text',text:'A note',facets:[{index:{byteStart:2,byteEnd:6},features:[{$type:'pub.leaflet.richtext.facet#footnote',footnoteId:'1',contentPlaintext:'Complete footnote text'}]}]}]}});
 const d=parsed(r.html);assert.ok(d.querySelector('em strong,strong em'));assert.equal(d.querySelector('th').textContent,'Heading cell');assert.ok(d.querySelector('ul li ul li').textContent.includes('Nested'));assert.ok(r.text.includes('Complete footnote text'));
});
if(fs.existsSync('/tmp/nfb-article137.json')) test('live Standard.site Welcome record and webpage retain every paragraph',()=>{
 const response=JSON.parse(fs.readFileSync('/tmp/nfb-article137.json','utf8'));const record=response.associatedRecords.find(r=>r.$type==='site.standard.document');const article={...record,url:'https://erickrouss.github.io/blog/welcome/'};const r=reader.render(article,fs.readFileSync('/tmp/nfb-welcome137.html','utf8')); for(const p of record.textContent.split(/\n\s*\n/).filter(Boolean)) assert.ok(r.text.includes(p.replace(/\s+/g,' ').trim()),p); assert.ok(r.usable);
});
console.log(`${count} article reader tests passed`);
