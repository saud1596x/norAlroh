(()=>{'use strict';const story=document.querySelector('.motion-story');if(!story)return;
const tabs=[...story.querySelectorAll('[data-feature]')],texts=[...story.querySelectorAll('.story-text')],arts=[...story.querySelectorAll('.art-scene')],count=story.querySelector('#dhikr-count'),dial=story.querySelector('.dial-value');let scene=0,elapsed=0,last=0,inView=false,countBefore=-1;const reduced=matchMedia('(prefers-reduced-motion: reduce)');
function show(index){scene=index;elapsed=0;story.dataset.scene=String(index);tabs.forEach((tab,i)=>tab.setAttribute('aria-pressed',String(i===index)));texts.forEach((text,i)=>{text.hidden=i!==index;text.classList.toggle('active',i===index)});arts.forEach((art,i)=>art.classList.toggle('active',i===index));countBefore=-1}
tabs.forEach((tab,i)=>tab.addEventListener('click',()=>show(i)));
new IntersectionObserver(entries=>{inView=entries[0].isIntersecting;story.classList.toggle('story-idle',!inView)},{threshold:.15}).observe(story);
function frame(time){const dt=Math.min((time-last)/1000,.06)||0;last=time;if(inView&&!document.hidden&&!document.body.classList.contains('paused')){elapsed+=dt;if(elapsed>=12&&!reduced.matches)show((scene+1)%3);if(scene===1){const n=Math.min(33,Math.floor(elapsed*3));if(n!==countBefore){countBefore=n;count.textContent=String(n);dial.style.strokeDashoffset=String(534*(1-n/33))}}}requestAnimationFrame(frame)}show(0);requestAnimationFrame(frame);
})();

