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
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'self'; script-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'">
<title>{e(doc['title'])} — {e(content['app'])}</title>
<meta name="description" content="{e(doc['intro'])}">
<link rel="stylesheet" href="site.css">
</head>
<body>
<a class="skip" href="#content">انتقل إلى المحتوى</a>
<header class="site-header"><div class="wrap header-inner"><a class="brand" href="support.html" aria-label="نور الروح — الدعم والمساعدة">{symbol}<span>نور الروح<span class="brand-small">مساحة للقراءة والذكر</span></span></a><nav class="nav" aria-label="صفحات المساعدة">{nav}</nav></div></header>
<main class="wrap" id="content">
<section class="motion-film" aria-label="عرض نور الروح"><div class="film-grain" aria-hidden="true"></div><div class="film-aura" aria-hidden="true"></div>
<div class="film-top"><span dir="ltr">NOOR ALRUH / THE EXPERIENCE</span><button class="motion-toggle" type="button" aria-pressed="false">إيقاف الحركة</button></div>
<div class="film-copy"><span class="film-eyebrow">نــور الــروح</span><h2>من سطر كود.<br><em>إلى نورٍ في يومك.</em></h2><p>تجربةٌ تُصنع بعناية. لتقرأ بطمأنينة.</p><a class="film-link" href="#policy-start">{e(doc['title'])}</a></div>
<div class="film-stage">
<div class="code-card code-card-back" dir="ltr" aria-hidden="true"><span>Reader.swift</span><pre><i>import</i> SwiftUI

<i>struct</i> NoorReader: View {{
  <i>var</i> body: some View {{
    MushafView()
      .readingComfort(.calm)
  }}
}}</pre></div>
<div class="laptop-visual" aria-label="عرض أكواد التصميم داخل جهاز ماك بوك"><div class="laptop-image"><img src="macbook.png" alt="جهاز MacBook Pro" width="860" height="900"></div><div class="laptop-code" dir="ltr"><div class="editor-toolbar"><span class="editor-lights">● ● ●</span><span>NoorAlruh / Reader.swift</span></div><div class="editor-sidebar">⌘<br>⌑<br>⏣</div><pre><span class="syntax-comment">// A little light, every day.</span>

<span class="syntax-keyword">import</span> SwiftUI

<span class="syntax-keyword">struct</span> <span class="syntax-name">NoorAlruh</span>: App {{
  <span class="syntax-keyword">var</span> body: some Scene {{
    WindowGroup {{
      <span class="syntax-name">MushafReader</span>()
        .environment(\\.layoutDirection, .rightToLeft)
    }}
  }}
}}<span class="code-cursor">▎</span></pre><div class="editor-status">Swift · SwiftUI <span>نور الروح</span></div></div></div>
<div class="film-phone"><div class="film-phone-inner"><img class="reader-screen" src="reader.png" alt="لقطة فعلية للمصحف داخل تطبيق نور الروح" width="945" height="2048"><div class="phone-intro"><img src="app-icon.png" alt="" width="100" height="100"><strong>نور الروح</strong><span>مساحة للقراءة والذكر</span></div></div></div>
<div class="floating-language lang-swift" dir="ltr">Swift</div><div class="floating-language lang-ui" dir="ltr">SwiftUI</div><div class="floating-language lang-python" dir="ltr">Python</div><div class="floating-language lang-js" dir="ltr">JavaScript</div>
<span class="orbit-word" dir="ltr">CRAFTED WITH CARE</span></div>
<div class="film-bottom"><span class="film-caption">كود. عناية. سكينة.</span><div class="film-progress" aria-hidden="true"><span></span></div><span dir="ltr">01 — 03</span></div></section>
<section class="experience-strip"><div><span>01 / القراءة</span><h2>مساحة للكلمة.<br>وراحة للعين.</h2><p>لقطة من المصحف داخل نور الروح.</p></div><div class="screen-detail"><img src="reader.png" alt="المصحف في تطبيق نور الروح" width="945" height="2048" loading="lazy"></div><div class="experience-mark" aria-hidden="true">نور<br>الروح</div></section>
<div class="document-heading" id="policy-start"><span class="eyebrow">{e(doc['eyebrow'])}</span><h1>{e(doc['title'])}</h1><p>{e(doc['intro'])}</p><div class="updated">آخر تحديث <time datetime="{e(content['updated'])}">9 أكتوبر 2026</time></div></div>
{summaries}
<div class="layout"><aside><details class="toc" open><summary>في هذه الصفحة</summary><ol>{toc}</ol></details></aside><article class="reading" aria-label="{e(doc['title'])}">{sections}</article></div>
<section class="contact-band" aria-label="التواصل مع الدعم"><div><h2>تحتاج مساعدة؟</h2><p>يسعدنا استقبال ملاحظتك أو سؤالك عن بياناتك.</p></div><a class="contact-button" href="mailto:{e(content['email'])}">تواصل مع الدعم <span aria-hidden="true">&nbsp;←</span></a></section>
</main>
<footer class="footer"><div class="wrap footer-inner"><div><div class="footer-brand">نور الروح</div><p>خطوات هادئة، ومعرفة واضحة بخياراتك.</p></div><div class="footer-links"><a href="privacy.html">الخصوصية</a><a href="terms.html">الشروط</a><a href="support.html">المساعدة</a></div></div></footer>
<script src="motion.js" defer></script>
</body></html>
'''
    (ROOT / (doc['id'] + '.html')).write_text(page)
(ROOT / 'index.html').write_text((ROOT / 'support.html').read_text())
print('Public privacy, terms and support pages generated; native app source unchanged.')
