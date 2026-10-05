// Optional local Chromium verification. Does not publish or test native iOS.
import fs from 'node:fs';
import path from 'node:path';
import {createServer} from 'node:http';
import {fileURLToPath, pathToFileURL} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const playwrightModule = process.env.NOOR_PLAYWRIGHT_MODULE;
if (!playwrightModule) throw new Error('Set NOOR_PLAYWRIGHT_MODULE to the installed Playwright index.mjs path.');
const {chromium} = await import(pathToFileURL(playwrightModule).href);
const legal = JSON.parse(fs.readFileSync(path.join(root, 'ios/Athar/app-legal.json'), 'utf8'));
const allowed = new Set(['index.html', ...legal.documents.map(document => document.id + '.html')]);
const server = createServer((request, response) => {
  const name = new URL(request.url, 'http://localhost').pathname.replace(/^\//, '') || 'index.html';
  if (!allowed.has(name)) {response.writeHead(404); response.end(); return;}
  response.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'});
  response.end(fs.readFileSync(path.join(root, 'support-site', name)));
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = 'http://127.0.0.1:' + server.address().port;
let browser;
const results = [];
try {
  browser = await chromium.launch({executablePath: process.env.NOOR_CHROMIUM || '/usr/bin/chromium', args: ['--no-sandbox']});
  for (const width of [320, 430, 1024]) {
    const context = await browser.newContext({viewport: {width, height: 900}});
    const page = await context.newPage();
    const remote = [];
    page.on('request', request => {if (/^https?:/.test(request.url()) && !request.url().startsWith(origin + '/')) remote.push(request.url());});
    for (const document of legal.documents) {
      const response = await page.goto(origin + '/' + document.id + '.html');
      if (response.status() !== 200) throw new Error('Local page did not load.');
      const checks = await page.evaluate(({document, legal}) => {
        const body = window.document.body;
        return {
          rightToLeft: window.document.documentElement.dir === 'rtl',
          languageArabic: window.document.documentElement.lang === 'ar',
          noHorizontalOverflow: body.scrollWidth <= innerWidth && window.document.documentElement.scrollWidth <= innerWidth,
          allSectionsPresent: document.sections.every(section => body.innerText.includes(section.title) && body.innerText.includes(section.text)),
          publisherPresent: body.innerText.includes(legal.publisherName),
          supportEmailCorrect: window.document.querySelector('a[href^="mailto:"]')?.getAttribute('href') === 'mailto:' + legal.contact.supportEmail,
          noTrackingScriptsFormsOrFrames: !window.document.querySelector('script, form, iframe'),
          privacyLinkAccessible: [...window.document.querySelectorAll('nav a')].some(link => link.getAttribute('href') === 'privacy.html')
        };
      }, {document, legal});
      if (Object.values(checks).some(value => !value)) throw new Error(JSON.stringify({id: document.id, width, checks}));
      results.push({page: document.id, width, checks});
    }
    if (remote.length) throw new Error('Static pages unexpectedly requested external resources.');
    await context.close();
  }
} finally {await browser?.close(); await new Promise(resolve => server.close(resolve));}
const report = {status: 'PASS', testedAt: new Date().toISOString(), scope: 'Local static support/privacy/terms HTML in Chromium; not a publicly deployed website or native iOS test.', layouts: results.length, results};
fs.writeFileSync(path.join(root, 'release/publishing-pages-check.json'), JSON.stringify(report, null, 2));
process.stdout.write(JSON.stringify({status: report.status, layouts: report.layouts, scope: report.scope}) + '\n');
