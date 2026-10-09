"""Build the public support pages without modifying native app legal resources."""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
content = json.loads((ROOT / "site-content.json").read_text())
e = html.escape
symbol = '<svg class="brand-symbol" viewBox="0 0 48 48" fill="none" aria-hidden="true"><path d="M24 3 29 11 38 10 37 19 45 24 37 29 38 38 29 37 24 45 19 37 10 38 11 29 3 24 11 19 10 10 19 11Z" stroke="currentColor" stroke-width="1.5"/><path d="M24 12 36 24 24 36 12 24Z" stroke="currentColor" stroke-width="1.2"/><circle cx="24" cy="24" r="5" stroke="currentColor" stroke-width="1.5"/></svg>'
for doc in content["documents"]:
    nav = ''.join(f'<a href="{e(d["id"])}.html"'+(' aria-current="page"' if d['id']==doc['id'] else '')+f'>{e(d["title"])}</a>' for d in content['documents'])
    toc = ''.join(f'<li><a href="#{e(s["id"])}">{e(s["title"])}</a></li>' for s in doc['sections'])
    def paragraph(text):
        safe = e(text).replace(e(content['email']), f'<a href="mailto:{e(content["email"])}"><bdi>{e(content["email"])}</bdi></a>')
        return '<p>'+safe+'</p>'
    sections = ''.join(f'<section class="section" id="{e(s["id"])}"><div class="section-head"><span class="section-number" aria-hidden="true">{i:02d}</span><h2>{e(s["title"])}</h2></div>'+''.join(paragraph(p) for p in s['paragraphs'])+'</section>' for i,s in enumerate(doc['sections'],1))
    summaries = '<div class="summary-grid" aria-label="الخصوصية باختصار">'+''.join(f'<div class="summary-card"><strong><span class="summary-marker" aria-hidden="true">✓</span>{e(title)}</strong><p>{e(text)}</p></div>' for title,text in doc['summary'])+'</div>' if doc['summary'] else ''
    page = f'''<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><meta name="color-scheme" content="light dark">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'">
<title>{e(doc['title'])} — {e(content['app'])}</title>
<meta name="description" content="{e(doc['intro'])}">
<link rel="stylesheet" href="site.css">
</head>
<body>
<a class="skip" href="#content">انتقل إلى المحتوى</a>
<header class="site-header"><div class="wrap header-inner"><a class="brand" href="support.html" aria-label="نور الروح — الدعم والمساعدة">{symbol}<span>نور الروح<span class="brand-small">مساحة للقراءة والذكر</span></span></a><nav class="nav" aria-label="صفحات المساعدة">{nav}</nav></div></header>
<main class="wrap" id="content">
<div class="hero"><div class="hero-copy"><span class="eyebrow">{e(doc['eyebrow'])}</span><h1>{e(doc['title'])}</h1><p>{e(doc['intro'])}</p><div class="updated"><span class="status-dot" aria-hidden="true"></span>آخر تحديث <time datetime="{e(content['updated'])}">9 أكتوبر 2026</time></div></div><div class="hero-art" aria-hidden="true"><div class="art-glow"></div><svg class="privacy-graphic" viewBox="0 0 480 440" fill="none"><g class="orbit"><circle cx="240" cy="220" r="172" stroke="#B9D4C8" stroke-dasharray="3 12"/><path d="M240 48a172 172 0 0 1 172 172" stroke="#C4A976" stroke-width="2"/><circle cx="240" cy="48" r="6" fill="#C4A976"/></g><g class="orbit-reverse"><path d="M98 220a142 142 0 0 1 284 0" stroke="#BCD9CD"/><path d="M98 220a142 142 0 0 0 284 0" stroke="#BCD9CD" stroke-dasharray="5 10"/></g><g class="graphic-core"><rect x="149" y="120" width="182" height="200" rx="42" fill="#143F34"/><rect x="157" y="128" width="166" height="184" rx="35" stroke="#4E7968"/><path d="M240 160 283 177v39c0 35-25 55-43 64-18-9-43-29-43-64v-39Z" fill="#EDF4E9" fill-opacity=".08" stroke="#D9C59B" stroke-width="2"/><path d="m220 214 14 14 28-29" stroke="#EDF4E9" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/></g><g class="float-card"><rect x="24" y="238" width="140" height="74" rx="18" fill="#FFFEF9" stroke="#DCE7DF"/><rect x="44" y="255" width="35" height="35" rx="11" fill="#E7EFE7"/><path d="m53 273 6 6 11-13" stroke="#315C4C" stroke-width="2" stroke-linecap="round"/><path d="M92 265h48M92 279h30" stroke="#A8BBB0" stroke-width="4" stroke-linecap="round"/></g><g class="float-card second"><rect x="306" y="83" width="150" height="74" rx="18" fill="#FFFEF9" stroke="#DCE7DF"/><circle cx="333" cy="110" r="7" fill="#D3B77D"/><path d="M326 128q7-9 14 0" stroke="#D3B77D" stroke-width="3" stroke-linecap="round"/><path d="M355 108h75M355 122h50" stroke="#A8BBB0" stroke-width="4" stroke-linecap="round"/></g><circle cx="366" cy="336" r="8" fill="#C4A976"/><path d="M105 100v16m-8-8h16M348 370v12m-6-6h12" stroke="#557963" stroke-width="2" stroke-linecap="round"/></svg><span class="art-caption">اختياراتك في مساحة واضحة</span></div></div>
{summaries}
<div class="layout"><aside><details class="toc" open><summary>في هذه الصفحة</summary><ol>{toc}</ol></details></aside><article class="reading" aria-label="{e(doc['title'])}">{sections}</article></div>
<section class="contact-band" aria-label="التواصل مع الدعم"><div><h2>تحتاج مساعدة؟</h2><p>يسعدنا استقبال ملاحظتك أو سؤالك عن بياناتك.</p></div><a class="contact-button" href="mailto:{e(content['email'])}">تواصل مع الدعم <span aria-hidden="true">&nbsp;←</span></a></section>
</main>
<footer class="footer"><div class="wrap footer-inner"><div><div class="footer-brand">نور الروح</div><p>خطوات هادئة، ومعرفة واضحة بخياراتك.</p></div><div class="footer-links"><a href="privacy.html">الخصوصية</a><a href="terms.html">الشروط</a><a href="support.html">المساعدة</a></div></div></footer>
</body></html>
'''
    (ROOT / (doc['id'] + '.html')).write_text(page)
(ROOT / 'index.html').write_text((ROOT / 'support.html').read_text())
print('Public privacy, terms and support pages generated; native app source unchanged.')
