'use strict';
const film=document.querySelector('.motion-film');
const toggle=document.querySelector('.motion-toggle');
if(film&&toggle){toggle.addEventListener('click',()=>{const paused=film.classList.toggle('motion-paused');toggle.setAttribute('aria-pressed',String(paused));toggle.textContent=paused?'تشغيل الحركة':'إيقاف الحركة';});}
if('IntersectionObserver' in window&&!window.matchMedia('(prefers-reduced-motion: reduce)').matches){const observer=new IntersectionObserver(items=>items.forEach(item=>{if(item.isIntersecting){item.target.classList.add('is-visible');observer.unobserve(item.target);}}),{threshold:.08});document.querySelectorAll('.summary-card,.section,.experience-strip,.contact-band').forEach(el=>{el.classList.add('reveal-item');observer.observe(el);});}
