(() => {
 const root=document.querySelector('.feature-cinema'); if(!root)return;
 const scenes=[...root.querySelectorAll('.cinema-scene')],buttons=[...root.querySelectorAll('[data-frame-button]')];
 const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
 let frame=0,elapsed=0,visible=false,paused=false,last=0;
 const steps=[['اختر الآية','تعمّق في معناها','احفظ موضعك'],['اخفِ الكلمات','استحضر الآية','استمع إلى تسجيلك'],['حدّد هدفك','اختبر تذكّرك','عُد للمراجعة'],['خطّط لوردك','أكّد قراءتك','تابع رحلتك'],['اختر ذكرك','تابع التكرارات','احفظ إنجازك'],['اختر مدينتك','تابع الصلاة القادمة','خصّص تنبيهك'],['اختر المشتتات','امنح وردك وقتًا','أكمل وردك'],['اختر المزامنة','احفظ تقدمك','عُد من جهازك']];
 const status=document.createElement('div');status.className='cinema-step';root.querySelector('.cinema-stage').append(status);
 const count=document.createElement('span');count.className='cinema-number';root.querySelector('.cinema-stage').append(count);
 function show(i){frame=i;elapsed=0;root.dataset.frame=i;root.dataset.step='0';scenes.forEach((s,n)=>{s.classList.toggle('current',n===i);s.setAttribute('aria-hidden',n!==i)});buttons.forEach((b,n)=>b.setAttribute('aria-pressed',n===i));status.textContent=steps[i][0];count.textContent=`${String(i+1).padStart(2,'0')} / 08`;}
 buttons.forEach((b,i)=>b.addEventListener('click',()=>show(i)));
 new IntersectionObserver(e=>{visible=e[0].isIntersecting;root.classList.toggle('playing',visible&&!paused&&!reduced)},{threshold:.25}).observe(root.querySelector('.cinema-stage'));
 document.getElementById('pause')?.addEventListener('click',()=>requestAnimationFrame(()=>{paused=document.getElementById('pause').getAttribute('aria-pressed')==='true';root.classList.toggle('playing',visible&&!paused&&!reduced)}));
 function tick(t){const dt=last?Math.min(t-last,100):0;last=t;if(visible&&!paused&&!reduced&&!document.hidden){elapsed+=dt;root.querySelector('.animated-count').textContent=Math.min(33,Math.floor(elapsed/240)).toLocaleString('ar');const step=Math.min(2,Math.floor(elapsed/3334));root.dataset.step=step;status.textContent=steps[frame][step];if(elapsed>=10000)show((frame+1)%scenes.length);}requestAnimationFrame(tick)}show(0);requestAnimationFrame(tick);
})();
