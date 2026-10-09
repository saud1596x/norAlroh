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
<section class="campaign" aria-label="نور الروح"><div class="campaign-halo" aria-hidden="true"></div><div class="campaign-copy"><span class="campaign-kicker">نــور الــروح</span><h2 class="campaign-title">وردك.<br><span>مساحة للروح.</span></h2><p>القرآن والأذكار، في تجربة واحدة.<br>خطوة صغيرة تضيء يومك.</p><a class="campaign-button" href="#policy-start">{e(doc['title'])} <span aria-hidden="true">↓</span></a></div><div class="phone-scene" aria-label="عرض هوية تطبيق نور الروح"><div class="phone-orbit" aria-hidden="true"></div><div class="phone-frame"><div class="phone-screen"><div class="phone-island" aria-hidden="true"></div><div class="screen-glow" aria-hidden="true"></div><img class="phone-app-icon" src="app-icon.png" width="120" height="120" alt="أيقونة تطبيق نور الروح"><strong class="phone-app-name">نور الروح</strong><span class="phone-tagline">مساحة للقراءة والذكر</span><div class="screen-line" aria-hidden="true"></div><span class="phone-caption">عرض لهوية التطبيق</span><div class="phone-home" aria-hidden="true"></div></div></div><span class="scene-label">N O O R &nbsp; A L R U H</span></div></section><div class="document-heading" id="policy-start"><span class="eyebrow">{e(doc['eyebrow'])}</span><h1>{e(doc['title'])}</h1><p>{e(doc['intro'])}</p><div class="updated">آخر تحديث <time datetime="{e(content['updated'])}">9 أكتوبر 2026</time></div></div>
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
