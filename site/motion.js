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

  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Runs onChange(true/false) as the element enters and leaves the viewport.
  const watch = (el, onChange, threshold = 0.25) => {
    if (!el) return;
    new IntersectionObserver(
      (entries) => entries.forEach((e) => onChange(e.isIntersecting)),
      { threshold },
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
      if (!running) return;
      i = (i + 1) % words.length;
      show(words[i]);
      t.later(tick, holdFor(words[i]));
    };
    const setRunning = (on) => {
      if (on === running) return;
      running = on;
      t.clear();
      if (on) t.later(tick, holdFor(words[i]));
    };
    watch(root, setRunning, 0.2);
    document.addEventListener('visibilitychange', () => setRunning(!document.hidden && root.getBoundingClientRect().top < innerHeight));
  }

  function promises() {
    const section = document.querySelector('.promises');
    watch(section, (on) => { if (on) section.classList.add('is-seen'); }, 0.3);
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
    const html = el.innerHTML;
    let n = 0;
    el.classList.add(busyClass);
    el.textContent = '';
    const step = () => {
      n += 1;
      el.textContent = units.slice(0, n).join(joiner);
      if (n < units.length) return t.later(step, ms);
      el.innerHTML = html;
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

    root.querySelectorAll('.chips').forEach((list) => {
      [...list.children].forEach((chip, k) => chip.style.setProperty('--d', `${k * CHIP_STAGGER_MS}ms`));
    });

    const enter = (n) => {
      if (n === 1) {
        ask.classList.remove('is-done');
        if (reduced) return ask.classList.add('is-done');
        reveal(ask, [...askText], '', TYPE_CHAR_MS, 'is-typing', t, () => {
          requestAnimationFrame(() => ask.classList.add('is-done'));
        });
      }
      if (n === 4 && !reduced) reveal(answer, answerText.split(' '), ' ', STREAM_WORD_MS, 'is-streaming', t);
    };

    // Puts both animated texts back to their full markup, so an interrupted animation never
    // leaves half a sentence behind.
    const resetTexts = () => {
      ask.innerHTML = askHTML;
      ask.classList.remove('is-typing');
      answer.innerHTML = answerHTML;
      answer.classList.remove('is-streaming');
    };

    const go = (n, animate = true) => {
      t.clear();
      resetTexts();
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
      if (animate) enter(n);
      else ask.classList.add('is-done');
      if (animate && autoplay && visible) t.later(() => go(n % LAST_STEP + 1), STEP_MS[n]);
    };

    const setAutoplay = (on) => {
      autoplay = on;
      root.classList.toggle('is-manual', !on);
      play.textContent = on ? 'Pause' : 'Play';
      play.setAttribute('aria-pressed', String(!on));
      go(step);
    };

    items.forEach((li) => li.querySelector('.step-btn').addEventListener('click', () => {
      autoplay = false;
      root.classList.add('is-manual');
      play.textContent = 'Play';
      play.setAttribute('aria-pressed', 'true');
      go(Number(li.dataset.stepItem));
    }));

    if (reduced) {
      root.classList.add('is-manual');
      go(LAST_STEP);
      return;
    }

    play.hidden = false;
    play.addEventListener('click', () => setAutoplay(!autoplay));
    go(1, false);
    let started = false;
    watch(stage, (on) => {
      visible = on;
      root.classList.toggle('is-paused', !on);
      if (on && !started) { started = true; go(1); return; }
      if (on && autoplay) go(step);
      if (!on) go(step, false);
    }, 0.15);
  }

  function deviceMap() {
    document.querySelectorAll('[data-map]').forEach((svg) => {
      if (typeof svg.pauseAnimations !== 'function') return;
      svg.pauseAnimations();
      if (!reduced) watch(svg, (on) => (on ? svg.unpauseAnimations() : svg.pauseAnimations()), 0.2);
    });
  }

  function sample() {
    const card = document.querySelector('[data-sample]');
    if (!card) return;
    const buttons = [...card.querySelectorAll('[data-show]')];
    const t = timers();
    let looping = !reduced;

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
    buttons.forEach((b) => b.addEventListener('click', () => {
      looping = false;
      t.clear();
      card.classList.remove('is-scanning');
      show(b.dataset.show);
    }));
    watch(card, (on) => {
      t.clear();
      card.classList.remove('is-scanning');
      if (on && looping) cycle();
      if (!on && looping) show('after');
    }, 0.5);
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

  menu();
  reader();
  promises();
  shelf();
  pipeline();
  deviceMap();
  sample();
  counters();
})();
