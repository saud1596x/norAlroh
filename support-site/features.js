(() => {
  const cards = document.querySelectorAll('.complete-card');
  const observer = new IntersectionObserver(entries => entries.forEach(entry => entry.target.classList.toggle('in-view', entry.isIntersecting)), { threshold: .12 });
  cards.forEach(card => observer.observe(card));
  const pause = document.getElementById('pause');
  if (pause) pause.addEventListener('click', () => requestAnimationFrame(() => {
    const stopped = pause.getAttribute('aria-pressed') === 'true';
    document.querySelectorAll('.feature-signal i,.feature-route i').forEach(el => el.style.animationPlayState = stopped ? 'paused' : '');
    document.querySelector('.complete-features')?.classList.toggle('motion-stopped', stopped);
  }));
})();
