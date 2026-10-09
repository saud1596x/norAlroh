(() => {
 const root=document.querySelector('.feature-cinema'); if(!root)return;
 const scenes=[...root.querySelectorAll('.cinema-scene')],buttons=[...root.querySelectorAll('[data-frame-button]')];
 const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
 let frame=0,elapsed=0,visible=false,paused=false,last=0;
 function show(i){frame=i;elapsed=0;root.dataset.frame=i;scenes.forEach((s,n)=>{s.classList.toggle('current',n===i);s.setAttribute('aria-hidden',n!==i)});buttons.forEach((b,n)=>b.setAttribute('aria-pressed',n===i));}
 buttons.forEach((b,i)=>b.addEventListener('click',()=>show(i)));
 new IntersectionObserver(e=>{visible=e[0].isIntersecting;root.classList.toggle('playing',visible&&!paused&&!reduced)},{threshold:.2}).observe(root);
 document.getElementById('pause')?.addEventListener('click',()=>requestAnimationFrame(()=>{paused=document.getElementById('pause').getAttribute('aria-pressed')==='true';root.classList.toggle('playing',visible&&!paused&&!reduced)}));
 function tick(t){const dt=last?Math.min(t-last,100):0;last=t;if(visible&&!paused&&!reduced&&!document.hidden){elapsed+=dt;root.querySelector('.animated-count').textContent=Math.min(33,Math.floor(elapsed/240)).toLocaleString('ar');if(elapsed>=10000)show((frame+1)%scenes.length);}requestAnimationFrame(tick)}requestAnimationFrame(tick);
})();
