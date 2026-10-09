(()=>{'use strict';
const $=s=>document.querySelector(s),mac=$('.macbook'),phone=$('.iphone'),source=$('#source'),button=$('#pause'),reduced=matchMedia('(prefers-reduced-motion: reduce)');
const template=`<div class="live-app" data-build="0"><div class="app-home"><div class="app-brand"><img src="assets/app-icon.png" alt=""><h3>نور الروح</h3><p>سكينة ترافق يومك</p></div><div class="app-card"><i>۞</i><div>القرآن الكريم<small>لحظتك مع القرآن</small></div></div><div class="app-card"><i>✧</i><div>أذكار اليوم<small>طمأنينة للقلب</small></div></div><div class="app-nav"><span>الرئيسية</span><span>القرآن</span><span>الأذكار</span></div></div><img class="app-reader" src="assets/reader.png" alt="المصحف داخل نور الروح"><div class="app-flash"></div></div>`;
for(const selector of ['.xcode-preview']){const container=$(selector);container.querySelector('img').remove();container.insertAdjacentHTML('afterbegin',template)}
const apps=[...document.querySelectorAll('.live-app')];
// Visual demonstration of applying code; this is not a live Swift compiler.
const blocks=[`import SwiftUI

struct NoorHome: View {
    var body: some View {
        VStack(spacing: 20) {
            NoorHeader(
                title: "نور الروح",
                subtitle: "سكينة ترافق يومك"
            )`, `

            FeatureCard(
                title: "القرآن الكريم",
                symbol: "book.closed"
            )
            FeatureCard(
                title: "أذكار اليوم",
                symbol: "sparkles"
            )`, `

            NoorTabBar()
        }
        .background(Color.noorCream)
        .tint(Color.noorBrown)
    }
}`, `

// الانتقال إلى المصحف
NavigationLink {
    MushafReader()
} label: {
    Text("القرآن الكريم")
}`];
const code=blocks.join(''),ends=blocks.map((_,i)=>blocks.slice(0,i+1).join('').length),escape=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
function highlight(s){return (s.match(/\/\/.*|"[^"\n]*"|\b(?:import|struct|var|some|let)\b|\b[A-Z]\w*\b|[^\w"]+|\w+|./g)||[]).map(t=>{const c=t.startsWith('//')?'code-comment':t.startsWith('"')?'code-string':/^(import|struct|var|some|let)$/.test(t)?'code-keyword':/^[A-Z]/.test(t)?'code-type':'';return c?`<span class="${c}">${escape(t)}</span>`:escape(t)}).join('')}
let charsBefore=-1,buildBefore=-1,elapsed=0,last=0,paused=false,pointer=0,px=0;
function draw(chars){if(chars===charsBefore)return;charsBefore=chars;source.innerHTML=code.slice(0,chars).split('\n').map((line,i)=>`<div class="code-line"><span class="code-no">${i+1}</span><span class="code-content">${highlight(line)}</span></div>`).join('');const editor=$('.xcode-code');editor.scrollTop=editor.scrollHeight-editor.clientHeight}
button.addEventListener('click',()=>{paused=!paused;button.setAttribute('aria-pressed',String(paused));button.setAttribute('aria-label',paused?'تشغيل الحركة':'تقليل الحركة');document.body.classList.toggle('paused',paused)});button.setAttribute('aria-label','تقليل الحركة');button.title='تقليل الحركة';
addEventListener('pointermove',e=>pointer=(e.clientX/innerWidth-.5)*2,{passive:true});document.addEventListener('visibilitychange',()=>last=performance.now());
const observer=new IntersectionObserver(entries=>entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('visible');observer.unobserve(entry.target)}}),{threshold:.12});document.querySelectorAll('.reveal').forEach(el=>observer.observe(el));
const path=$('#connection-path'),spark=$('#code-spark');
function frame(time){const dt=Math.min((time-last)/1000,.05)||0;last=time;if(!paused&&!document.hidden)elapsed=(elapsed+dt)%34;
const segment=Math.min(3,Math.floor(elapsed/6)),start=segment?ends[segment-1]:0,end=ends[segment],fraction=Math.min(1,Math.max(0,(elapsed-segment*6)/4.5));const chars=elapsed>=24?code.length:Math.floor(start+(end-start)*fraction);draw(chars);
const build=ends.filter(e=>chars>=e).length;if(build!==buildBefore){buildBefore=build;mac.dataset.build=String(build);apps.forEach(app=>{app.dataset.build=String(build);app.classList.remove('build-pulse');void app.offsetWidth;app.classList.add('build-pulse')})}
if(!paused&&!reduced.matches){px+=(pointer-px)*.025;const t=elapsed;if(phone)phone.style.transform=`translateY(${Math.sin(t*.65)*9}px) translateX(${Math.sin(t*.26)*5}px) rotate(${Math.sin(t*.3)*2+px}deg) rotateY(${Math.sin(t*.35)*4}deg) scale(${1+Math.sin(t*.22)*.025})`;mac.style.transform=`translateY(${Math.sin(t*.38)*4}px) rotate(${Math.sin(t*.2)*.35}deg)`}
const a=$('.xcode-code').getBoundingClientRect(),b=$('.xcode-preview').getBoundingClientRect(),x1=a.right,y1=a.top+a.height*.75,x2=b.left,y2=b.top+b.height*.6;const origin=$('#experience').getBoundingClientRect();path.setAttribute('d',`M ${x1-origin.left} ${y1-origin.top} C ${x1+35-origin.left} ${y1-35-origin.top}, ${x2-35-origin.left} ${y2+35-origin.top}, ${x2-origin.left} ${y2-origin.top}`);if(!paused){const length=path.getTotalLength(),point=path.getPointAtLength((elapsed%3/3)*length);spark.setAttribute('cx',point.x);spark.setAttribute('cy',point.y)}
requestAnimationFrame(frame)}requestAnimationFrame(frame);
})();
