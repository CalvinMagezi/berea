// Motion for the Berea site. Every piece reads correctly without this file; it only animates.
(() => {
  const READER_WORD_MS = 900;
  const READER_HOLD_MS = 1900;
  const READER_LONG_MS = 3600;
  const TYPE_CHAR_MS = 34;
  const STREAM_WORD_MS = 70;
  const STEP_MS = { 1: 5600, 2: 5000, 3: 5200, 4: 6400, 5: 6500 };
  const CHIP_STAGGER_MS = 70;
  const SAMPLE_BEFORE_MS = 2200;
  const SAMPLE_SCAN_MS = 900;
  const SAMPLE_LOOP_MS = 9000;
  const COUNT_MS = 900;
  const LAST_STEP = 5;
  const MOTION_KEY = 'berea-motion-off';

  const html = document.documentElement;
  html.classList.add('motion');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // One page-wide switch for every looping animation, remembered for this browser only.
  const motion = {
    off: reduced,
    listeners: [],
    set(off) {
      this.off = off;
      html.classList.toggle('motion-off', off);
      try { localStorage.setItem(MOTION_KEY, off ? '1' : '0'); } catch { /* storage may be blocked */ }
      this.listeners.forEach((fn) => fn(off));
    },
    onChange(fn) { this.listeners.push(fn); },
  };
  if (!reduced) {
    try { motion.off = localStorage.getItem(MOTION_KEY) === '1'; } catch { /* storage may be blocked */ }
    html.classList.toggle('motion-off', motion.off);
  }

  // Runs onChange(true/false) as the element enters and leaves the viewport.
  const watch = (el, onChange, threshold = 0.25, rootMargin = '0px') => {
    if (!el) return;
    new IntersectionObserver(
      (entries) => entries.forEach((e) => onChange(e.isIntersecting)),
      { threshold, rootMargin },
    ).observe(el);
  };

  const timers = () => {
    const ids = new Set();
    return {
      later(fn, ms) {
        const id = setTimeout(() => { ids.delete(id); fn(); }, ms);
        ids.add(id);
      },
      clear() { ids.forEach(clearTimeout); ids.clear(); },
    };
  };

  function motionToggles() {
    const buttons = [...document.querySelectorAll('[data-motion-toggle]')];
    if (reduced) return;
    const label = () => buttons.forEach((b) => { b.textContent = motion.off ? 'Play motion' : 'Pause motion'; });
    buttons.forEach((b) => {
      b.hidden = false;
      b.addEventListener('click', () => { motion.set(!motion.off); label(); });
    });
    label();
  }

  function menu() {
    const details = document.querySelector('.menu');
    if (!details) return;
    details.querySelectorAll('a').forEach((a) => a.addEventListener('click', () => { details.open = false; }));
    document.addEventListener('click', (e) => { if (!details.contains(e.target)) details.open = false; });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') details.open = false; });
  }

  function reader() {
    const root = document.querySelector('[data-reader]');
    if (!root || reduced) return;
    const words = [...root.querySelectorAll('.w')];
    const focus = root.querySelector('.reader-focus');
    const greek = root.querySelector('[data-focus="greek"]');
    const gloss = root.querySelector('[data-focus="gloss"]');
    const t = timers();
    let i = words.findIndex((w) => w.classList.contains('is-on'));
    let inView = false;
    let running = false;

    const holdFor = (w) => {
      if (w.dataset.hold === 'long') return READER_LONG_MS;
      return w.hasAttribute('data-hold') ? READER_HOLD_MS : READER_WORD_MS;
    };
    const show = (w) => {
      words.forEach((x) => x.classList.toggle('is-on', x === w));
      greek.textContent = w.firstChild.textContent.trim().replace(/[,.;·]$/, '');
      gloss.textContent = w.querySelector('small').textContent;
      focus.classList.remove('is-changing');
      void focus.offsetWidth;
      focus.classList.add('is-changing');
    };
    const tick = () => {
      i = (i + 1) % words.length;
      show(words[i]);
      t.later(tick, holdFor(words[i]));
    };
    const sync = () => {
      const should = inView && !document.hidden && !motion.off;
      if (should === running) return;
      running = should;
      t.clear();
      if (should) t.later(tick, holdFor(words[i]));
    };
    watch(root, (on) => { inView = on; sync(); }, 0.2);
    document.addEventListener('visibilitychange', sync);
    motion.onChange(sync);
  }

  function promises() {
    const section = document.querySelector('.promises');
    const grid = section?.querySelector('.promise-grid');
    watch(grid, (on) => { if (on) section.classList.add('is-seen'); }, 0, '0px 0px -15% 0px');
  }

  function shelf() {
    const list = document.querySelector('[data-shelf]');
    const nav = document.querySelector('.shelf-nav');
    if (!list || !nav) return;
    nav.hidden = false;
    const prev = nav.querySelector('[data-shelf-prev]');
    const next = nav.querySelector('[data-shelf-next]');
    const page = () => list.querySelector('li').getBoundingClientRect().width * 2;
    const update = () => {
      prev.disabled = list.scrollLeft < 4;
      next.disabled = list.scrollLeft + list.clientWidth > list.scrollWidth - 4;
    };
    prev.addEventListener('click', () => list.scrollBy({ left: -page(), behavior: reduced ? 'auto' : 'smooth' }));
    next.addEventListener('click', () => list.scrollBy({ left: page(), behavior: reduced ? 'auto' : 'smooth' }));
    list.addEventListener('scroll', update, { passive: true });
    update();
  }

  // Shows text one unit at a time, then restores the original markup.
  function reveal(el, units, joiner, ms, busyClass, t, done) {
    const original = el.innerHTML;
    let n = 0;
    el.classList.add(busyClass);
    el.textContent = '';
    const step = () => {
      n += 1;
      el.textContent = units.slice(0, n).join(joiner);
      if (n < units.length) return t.later(step, ms);
      el.innerHTML = original;
      el.classList.remove(busyClass);
      done?.();
    };
    t.later(step, ms);
  }

  function pipeline() {
    const root = document.querySelector('[data-pipeline]');
    if (!root) return;
    const stage = root.querySelector('.stage');
    const label = root.querySelector('[data-stage-label]');
    const items = [...root.querySelectorAll('[data-step-item]')];
    const play = root.querySelector('[data-play]');
    const ask = root.querySelector('[data-type]');
    const answer = root.querySelector('[data-stream]');
    const askText = ask.textContent;
    const askHTML = ask.innerHTML;
    const answerText = answer.textContent;
    const answerHTML = answer.innerHTML;
    const t = timers();
    let step = 1;
    let autoplay = !reduced;
    let visible = false;
    let started = false;

    root.querySelectorAll('.chips').forEach((list) => {
      [...list.children].forEach((chip, k) => chip.style.setProperty('--d', `${k * CHIP_STAGGER_MS}ms`));
    });

    // Puts both animated texts back to their full markup, so an interrupted animation never
    // leaves half a sentence behind.
    const settle = () => {
      t.clear();
      ask.innerHTML = askHTML;
      ask.classList.remove('is-typing');
      ask.classList.add('is-done');
      answer.innerHTML = answerHTML;
      answer.classList.remove('is-streaming');
    };

    const enter = (n) => {
      if (n === 1) {
        ask.classList.remove('is-done');
        reveal(ask, [...askText], '', TYPE_CHAR_MS, 'is-typing', t, () => {
          requestAnimationFrame(() => ask.classList.add('is-done'));
        });
      }
      if (n === 4) reveal(answer, answerText.split(' '), ' ', STREAM_WORD_MS, 'is-streaming', t);
    };

    const running = () => autoplay && visible && !motion.off;

    const go = (n, animate = true) => {
      settle();
      step = n;
      stage.dataset.step = String(n);
      label.textContent = `Step ${n} of ${LAST_STEP}`;
      items.forEach((li) => {
        li.classList.remove('is-active');
        li.style.setProperty('--step-ms', `${STEP_MS[li.dataset.stepItem]}ms`);
        li.querySelector('.step-btn').removeAttribute('aria-current');
      });
      void root.offsetWidth;
      const active = items[n - 1];
      active.classList.add('is-active');
      active.querySelector('.step-btn').setAttribute('aria-current', 'step');
      if (animate && !reduced) enter(n);
      if (animate && running()) t.later(() => go(n % LAST_STEP + 1), STEP_MS[n]);
    };

    const showManual = (manual) => {
      root.classList.toggle('is-manual', manual);
      play.textContent = manual ? 'Play' : 'Pause';
    };

    items.forEach((li) => {
      const button = li.querySelector('.step-btn');
      button.disabled = false;
      button.addEventListener('click', () => {
        autoplay = false;
        started = true;
        showManual(true);
        go(Number(li.dataset.stepItem));
        const box = stage.getBoundingClientRect();
        if (box.bottom < 0 || box.top > innerHeight) stage.scrollIntoView({ block: 'nearest', behavior: reduced ? 'auto' : 'smooth' });
      });
    });

    if (reduced) {
      showManual(true);
      go(LAST_STEP, false);
      return;
    }

    play.hidden = false;
    play.addEventListener('click', () => {
      autoplay = !autoplay;
      showManual(!autoplay);
      // Pausing freezes the current step where it is; playing moves on from it.
      if (autoplay) go(step % LAST_STEP + 1);
      else settle();
    });
    motion.onChange((off) => {
      root.classList.toggle('is-paused', off || !visible);
      if (off) settle();
      else if (running()) go(step);
    });

    go(1, false);
    watch(stage, (on) => {
      visible = on;
      root.classList.toggle('is-paused', !on || motion.off);
      if (!on) return settle();
      if (!started && running()) { started = true; return go(1); }
      if (running()) go(step);
    }, 0.15);
  }

  function deviceMap() {
    document.querySelectorAll('[data-map]').forEach((svg) => {
      if (typeof svg.pauseAnimations !== 'function') return;
      svg.pauseAnimations();
      if (reduced) return;
      let inView = false;
      const sync = () => (inView && !motion.off ? svg.unpauseAnimations() : svg.pauseAnimations());
      watch(svg, (on) => { inView = on; sync(); }, 0.2);
      motion.onChange(sync);
    });
  }

  function sample() {
    const card = document.querySelector('[data-sample]');
    if (!card) return;
    const buttons = [...card.querySelectorAll('[data-show]')];
    const t = timers();
    let looping = !reduced;
    let inView = false;

    const show = (state) => {
      card.dataset.state = state;
      buttons.forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.show === state)));
    };
    const cycle = () => {
      show('before');
      t.later(() => card.classList.add('is-scanning'), SAMPLE_BEFORE_MS);
      t.later(() => { card.classList.remove('is-scanning'); show('after'); }, SAMPLE_BEFORE_MS + SAMPLE_SCAN_MS);
      t.later(cycle, SAMPLE_LOOP_MS);
    };
    const sync = () => {
      t.clear();
      card.classList.remove('is-scanning');
      if (looping && inView && !motion.off) cycle();
      else if (looping) show('after');
    };
    buttons.forEach((b) => b.addEventListener('click', () => {
      looping = false;
      sync();
      show(b.dataset.show);
    }));
    watch(card, (on) => { inView = on; sync(); }, 0.5);
    motion.onChange(sync);
  }

  function counters() {
    const table = document.querySelector('.numbers');
    if (!table || reduced) return;
    const cells = [...table.querySelectorAll('[data-count]')];
    let done = false;
    watch(table, (on) => {
      if (!on || done) return;
      done = true;
      const start = performance.now();
      const frame = (now) => {
        const p = Math.min(1, (now - start) / COUNT_MS);
        cells.forEach((c) => { c.textContent = String(Math.round(Number(c.dataset.count) * p)); });
        if (p < 1) requestAnimationFrame(frame);
      };
      requestAnimationFrame(frame);
    }, 0.4);
  }

  motionToggles();
  menu();
  reader();
  promises();
  shelf();
  pipeline();
  deviceMap();
  sample();
  counters();
})();
