// Page-local behaviour for the Berea build. The engine pins the acts; this file draws the bespoke
// parts. Every scroll-driven value here is eased toward its target each frame, so a notched wheel
// glides instead of stepping. Nothing here runs on a timer.
(() => {
  const EASE = 0.14;
  const SETTLE = 0.0005;
  const MAX_DPR = 2;
  const FILM_FRAMES = 120;
  const FILM_SRC = (i) => `images/film/${String(i).padStart(3, '0')}.webp`;
  const FILM_PASSES = [16, 8, 4, 2, 1];
  const MOTE_COUNT = 46;
  const MOTE_RISE_PX = 260;
  const MOTE_SWAY = 6;
  const STEPS = 5;
  const SCENE_FADE = 0.12;
  const TYPE_END = 0.45;
  const STREAM_END = 0.85;
  const CHIP_STEP = 0.08;
  const CHIP_FADE = 0.12;
  const VERSE_AT = [0.5, 0.66];
  const VERSE_FADE = 0.14;
  const SOFT_EDGE = 6;
  const PEAK_HANDOVER = 0.8;
  const PEAK_FOCUS_P = 0.88;
  const DEMO_FADE = 0.08;
  const RESULT_VERSES = 3;
  const DEMO = [
    { at: 0.24, text: '2 Hezekiah 4:1' },
    { at: 0.44, text: '“God so loved the world that He gave His only Son” (John 3:16)' },
    { at: 0.64, text: 'Psalm 151' },
  ];

  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  ScrollCraft.mount(document.body);

  const clamp01 = (x) => Math.min(1, Math.max(0, x));
  const escapeHtml = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // Pinned-travel progress of an act, measured from scroll directly so it never waits on the engine.
  const pinned = (act) => {
    const travel = Math.max(act.offsetHeight - innerHeight, 1);
    return clamp01((scrollY - act.offsetTop) / travel);
  };

  // A value that chases its target a fixed fraction per frame; reduced motion jumps straight there.
  function eased(read) {
    let value = read();
    return {
      step() {
        const target = read();
        if (reduced || Math.abs(target - value) < SETTLE) value = target;
        else value += (target - value) * EASE;
        return value;
      },
      get value() { return value; },
    };
  }

  // Runs fn every frame while el is on screen, and once more as it leaves.
  function whileVisible(el, fn) {
    let raf = 0;
    const loop = () => { fn(); raf = requestAnimationFrame(loop); };
    new IntersectionObserver(([e]) => {
      cancelAnimationFrame(raf);
      if (e.isIntersecting) raf = requestAnimationFrame(loop);
      else fn();
    }).observe(el);
  }

  function sizeCanvas(canvas, ctx) {
    const dpr = Math.min(devicePixelRatio || 1, MAX_DPR);
    canvas.width = Math.round(canvas.clientWidth * dpr);
    canvas.height = Math.round(canvas.clientHeight * dpr);
    ctx.setTransform(1, 0, 0, 1, 0, 0);
  }

  // Splits an element's text into per-character spans, keeping inline markup such as <mark>.
  function splitChars(el) {
    const spans = [];
    const walk = (node) => {
      for (const child of [...node.childNodes]) {
        if (child.nodeType !== Node.TEXT_NODE) { walk(child); continue; }
        const frag = document.createDocumentFragment();
        for (const ch of child.textContent) {
          const s = document.createElement('span');
          s.className = 'ch';
          s.textContent = ch;
          frag.append(s);
          spans.push(s);
        }
        child.replaceWith(frag);
      }
    };
    walk(el);
    return spans;
  }

  function splitWords(el) {
    const words = el.textContent.split(' ');
    el.textContent = '';
    return words.map((w, i) => {
      const s = document.createElement('span');
      s.className = 'ch';
      s.textContent = i < words.length - 1 ? `${w} ` : w;
      el.append(s);
      return s;
    });
  }

  // Each unit fades in over a few neighbours, so a reveal reads as a soft sweep, not a ticker.
  function sweep(units, amount) {
    const edge = amount * (units.length + SOFT_EDGE);
    units.forEach((u, i) => { u.style.opacity = clamp01((edge - i) / SOFT_EDGE).toFixed(3); });
  }

  // The hero film: 120 stills drawn from eased progress, blending neighbours for in-between frames.
  function film() {
    const canvas = document.querySelector('[data-film]');
    // Under reduced motion the poster holds the frame and no stills are fetched.
    if (!canvas || reduced) return;
    const act = canvas.closest('[data-sc-act]');
    const stage = canvas.closest('[data-sc-stage]');
    const ctx = canvas.getContext('2d');
    const frames = new Array(FILM_FRAMES);
    const load = (i) => {
      if (frames[i]) return;
      const img = new Image();
      img.decoding = 'async';
      img.onload = () => { img.ready = true; drawn = -1; };
      img.src = FILM_SRC(i + 1);
      frames[i] = img;
    };
    // Coarse frames first so the whole move is scrubbable early, then the gaps fill in.
    FILM_PASSES.forEach((stride) => { for (let i = 0; i < FILM_FRAMES; i += stride) load(i); });
    load(FILM_FRAMES - 1);

    const nearest = (i) => {
      for (let d = 0; d < FILM_FRAMES; d++) {
        if (frames[i - d]?.ready) return frames[i - d];
        if (frames[i + d]?.ready) return frames[i + d];
      }
      return null;
    };
    const cover = (img, alpha) => {
      const scale = Math.max(canvas.width / img.naturalWidth, canvas.height / img.naturalHeight);
      const w = img.naturalWidth * scale;
      const h = img.naturalHeight * scale;
      ctx.globalAlpha = alpha;
      ctx.drawImage(img, (canvas.width - w) / 2, (canvas.height - h) / 2, w, h);
    };

    // The film runs across the stage's whole visible life, so it keeps moving as the act leaves.
    const life = () => clamp01((scrollY - act.offsetTop) / act.offsetHeight);
    const progress = eased(life);
    let drawn = -1;
    const resize = () => { sizeCanvas(canvas, ctx); drawn = -1; };
    resize();
    addEventListener('resize', resize);

    const render = () => {
      const pos = progress.step() * (FILM_FRAMES - 1);
      if (Math.abs(pos - drawn) < 0.01) return;
      const i = Math.floor(pos);
      const base = frames[i]?.ready ? frames[i] : nearest(i);
      if (!base) return;
      cover(base, 1);
      const next = frames[i + 1];
      const blend = pos - i;
      if (next?.ready && blend > 0.01) cover(next, blend);
      ctx.globalAlpha = 1;
      drawn = pos;
      canvas.classList.add('is-drawn');
      stage.dataset.scVerifyState = pos.toFixed(1);
    };
    whileVisible(act, render);
  }

  function motes() {
    const canvas = document.querySelector('[data-motes]');
    if (!canvas || reduced) return;
    const act = canvas.closest('[data-sc-act]');
    const ctx = canvas.getContext('2d');
    const seeds = Array.from({ length: MOTE_COUNT }, (_, i) => ({
      x: (i * 0.618034) % 1,
      y: (i * 0.381966 + 0.13) % 1,
      r: 0.6 + ((i * 7) % 5) * 0.35,
      depth: 0.4 + ((i * 3) % 7) / 10,
      phase: i * 1.7,
    }));
    const progress = eased(() => pinned(act));
    let drawnAt = -1;
    const resize = () => {
      drawnAt = -1;
      sizeCanvas(canvas, ctx);
      const dpr = canvas.width / Math.max(canvas.clientWidth, 1);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    addEventListener('resize', resize);
    whileVisible(act, () => {
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
      const p = progress.step();
      if (Math.abs(p - drawnAt) < SETTLE) return;
      drawnAt = p;
      ctx.clearRect(0, 0, w, h);
      for (const m of seeds) {
        // Nearer motes rise faster against the camera move: the atmosphere has its own rate. They
        // move only with scroll, so nothing on the page animates without the reader.
        const y = (((m.y * h - p * MOTE_RISE_PX * m.depth) % h) + h) % h;
        const x = m.x * w + Math.sin(p * MOTE_SWAY + m.phase) * 12 * m.depth;
        const glow = 0.18 + 0.32 * m.depth * (0.6 + 0.4 * Math.sin(m.phase));
        ctx.fillStyle = `rgba(243, 208, 140, ${glow.toFixed(3)})`;
        ctx.beginPath();
        ctx.arc(x, y, m.r * m.depth * 1.6, 0, Math.PI * 2);
        ctx.fill();
      }
    });
  }

  // One real run, five scenes that crossfade continuously with scroll.
  function method() {
    const act = document.querySelector('[data-method]');
    if (!act) return;
    const stage = act.querySelector('[data-sc-stage]');
    const items = [...act.querySelectorAll('.steps li')];
    const scenes = [...act.querySelectorAll('.scene')];
    const askChars = splitChars(act.querySelector('[data-typed]'));
    const answerWords = splitWords(act.querySelector('[data-streamed]'));
    const verses = [...act.querySelectorAll('.verse')];
    const chips = [...act.querySelectorAll('.chips li')];
    const meter = act.querySelector('[data-meter]');
    const progress = eased(() => pinned(act));
    let last = -1;

    // Scenes hand over without overlapping: the old one clears before the new one arrives.
    const sceneOpacity = (k, pos) => {
      const fadeIn = k === 1 ? 1 : clamp01((pos - (k - 1)) / SCENE_FADE);
      const fadeOut = k === STEPS ? 1 : clamp01((k - pos) / SCENE_FADE);
      return Math.min(fadeIn, fadeOut);
    };
    const askMarks = [...act.querySelectorAll('[data-typed] mark')];

    const render = () => {
      const p = reduced ? 1 : progress.step();
      if (Math.abs(p - last) < SETTLE) return;
      last = p;
      const pos = p * STEPS;
      const step = Math.min(STEPS, Math.floor(pos) + 1);
      const local = clamp01(pos - (step - 1));
      stage.dataset.scVerifyState = pos.toFixed(2);
      items.forEach((li, i) => li.classList.toggle('is-on', i + 1 === step));
      scenes.forEach((s, i) => {
        const o = sceneOpacity(i + 1, pos);
        s.style.opacity = o.toFixed(3);
        s.style.transform = `translateY(${((1 - o) * 10).toFixed(1)}px)`;
        s.style.visibility = o > 0.001 ? 'visible' : 'hidden';
      });
      const first = step === 1 ? local : 1;
      sweep(askChars, clamp01(first / TYPE_END));
      askMarks.forEach((m) => { m.style.opacity = m.lastElementChild?.style.opacity ?? '1'; });
      verses.forEach((v, i) => {
        const o = clamp01((first - VERSE_AT[i]) / VERSE_FADE);
        v.style.opacity = o.toFixed(3);
        v.style.transform = `translateX(${((1 - o) * -8).toFixed(1)}px)`;
      });
      const second = step === 2 ? local : step > 2 ? 1 : 0;
      chips.forEach((c, i) => {
        const o = clamp01((second - i * CHIP_STEP) / CHIP_FADE);
        c.style.opacity = o.toFixed(3);
        c.style.transform = `scale(${(0.95 + 0.05 * o).toFixed(3)})`;
      });
      const third = step === 3 ? local : step > 3 ? 1 : 0;
      meter.style.transform = `scaleX(${clamp01(third / 0.6).toFixed(3)})`;
      const fourth = step === 4 ? local : step > 4 ? 1 : 0;
      sweep(answerWords, clamp01(fourth / STREAM_END));
    };
    whileVisible(act, render);
  }

  // The live check. Book text is fetched from this site on demand and cached.
  async function peak() {
    const act = document.querySelector('[data-peak]');
    if (!act) return;
    const stage = act.querySelector('[data-sc-stage]');
    const input = act.querySelector('[data-input]');
    const run = act.querySelector('[data-run]');
    const list = act.querySelector('[data-results]');
    const getJson = async (path) => {
      const r = await fetch(path);
      if (!r.ok) throw new Error(`${path} returned ${r.status}`);
      return r.json();
    };
    let books;
    let index;
    try {
      [books, index] = await Promise.all([getJson('data/books.json'), getJson('data/index.json')]);
    } catch (e) {
      run.disabled = true;
      input.disabled = true;
      list.innerHTML = `<li class="result"><p class="result-verdict">The check could not load its Bible data (${escapeHtml(String(e.message || e))}). Reload the page to try again.</p></li>`;
      return;
    }
    const checker = BereaCheck.create(books, index);
    const cache = new Map();
    const loadBook = (id) => {
      if (!cache.has(id)) cache.set(id, getJson(`data/bible/${id}.json`));
      return cache.get(id);
    };

    const verdict = (r) => {
      const parts = [];
      if (r.unknownBooks.length) parts.push('There is no such book in the Bible.');
      if (r.unverified.length) parts.push(`${r.unverified.join(', ')} does not exist in the Berean Standard Bible.`);
      if (r.corrected.length) parts.push('The quotation was not word for word, so Berea puts back the exact words.');
      if (r.badQuotes.length) parts.push('The quotation is not in the verse it cites, so Berea marks it.');
      if (!parts.length && r.verified.length) parts.push(`Verified: ${r.verified.join(', ')}.`);
      if (!parts.length) parts.push('No reference found. Add one the way an answer would cite it, such as John 3:16.');
      return parts.join(' ');
    };

    const markup = (text) => escapeHtml(text)
      .replace(/\[unverified: ([^\]]+)\]/g, '<span class="fake">$1</span><span class="mark mark--bad">unverified</span>')
      .replace(/ \[quote corrected\]/g, '<span class="mark mark--ok">quote corrected</span>')
      .replace(/ \[unverified quote\]/g, '<span class="mark mark--bad">not word for word</span>');

    const card = (label, typed, r) => {
      const li = document.createElement('li');
      li.className = 'result';
      const verses = r.passages.slice(0, RESULT_VERSES).map((v) =>
        `<p class="result-verse"><b>${escapeHtml(v.label)}, BSB</b>${escapeHtml(v.text)}</p>`).join('');
      li.innerHTML = `<p class="result-in">${label}: ${escapeHtml(typed)}</p>
        <p class="result-out">${markup(r.text)}</p>
        <p class="result-verdict">${escapeHtml(verdict(r))}</p>${verses}`;
      return li;
    };

    // The examples sit in fixed slots from the start, so revealing them never pushes the box around.
    let demo = [];
    try {
      demo = await Promise.all(DEMO.map(async (d) => ({ ...d, el: card('Example', d.text, await checker.check(d.text, loadBook)) })));
      demo.forEach((d) => { d.el.classList.add('result--demo'); list.append(d.el); });
    } catch (e) {
      list.innerHTML = `<li class="result"><p class="result-verdict">The examples could not load (${escapeHtml(String(e.message || e))}). The box still works.</p></li>`;
    }

    let manual = false;
    const takeOver = () => {
      if (manual) return;
      manual = true;
      demo.forEach((d) => { d.el.style.opacity = '1'; d.el.style.transform = 'none'; });
    };

    const submit = async () => {
      const value = input.value.trim();
      if (!value) return input.focus();
      takeOver();
      run.disabled = true;
      try {
        list.prepend(card('You typed', value, await checker.check(value, loadBook)));
      } catch (e) {
        const li = document.createElement('li');
        li.className = 'result';
        li.innerHTML = `<p class="result-verdict">That check could not finish: ${escapeHtml(String(e.message || e))}.</p>`;
        list.prepend(li);
      } finally {
        run.disabled = false;
        list.scrollTop = 0;
      }
    };
    run.addEventListener('click', submit);
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); submit(); } });

    // A pinned stage keeps the box at one screen position, so focus parks the act where it is open.
    input.addEventListener('focus', () => {
      takeOver();
      if (reduced || pinned(act) >= PEAK_HANDOVER) return;
      scrollTo({ top: act.offsetTop + (act.offsetHeight - innerHeight) * PEAK_FOCUS_P, behavior: 'instant' });
    });

    const progress = eased(() => pinned(act));
    let last = -1;
    const render = () => {
      const p = reduced ? 1 : progress.step();
      if (manual || Math.abs(p - last) < SETTLE) return;
      last = p;
      demo.forEach((d) => {
        const o = clamp01((p - d.at) / DEMO_FADE);
        d.el.style.opacity = o.toFixed(3);
        d.el.style.transform = `translateY(${((1 - o) * 12).toFixed(1)}px)`;
      });
      input.placeholder = p >= PEAK_HANDOVER ? 'Your turn: any reference, with or without a quotation' : 'Try “2 Hezekiah 4:1” or a verse you know';
      stage.dataset.scVerifyState = p.toFixed(2);
    };
    whileVisible(act, render);
  }

  film();
  motes();
  method();
  peak();
})();
