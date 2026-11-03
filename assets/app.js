(function () {
  'use strict';

  var CHAPTERS = [
    { n: 0, file: 'docs/00-setup.md', title: '环境与 Foundry 速览', short: '环境与 Foundry', min: 20, tests: 5,
      desc: '装好 Foundry，跑通第一个测试，掌握 prank、deal、expectRevert 等常用作弊码。', tags: ['forge', 'cheatcodes'] },
    { n: 1, file: 'docs/01-blockchain-evm.md', title: '区块链与 EVM 心智模型', short: '区块链与 EVM', min: 60, tests: 8,
      desc: '账户、交易、gas、存储布局、函数选择器，用代码复现 CREATE2 地址公式。', tags: ['EVM', 'CREATE2', 'Uniswap pairFor'] },
    { n: 2, file: 'docs/02-solidity-core.md', title: 'Solidity 核心语法', short: 'Solidity 核心语法', min: 75, tests: 13,
      desc: '数据位置、可见性、错误处理、发送 ETH 的正确姿势，动手实现 WETH9。', tags: ['WETH9', 'storage/memory'] },
    { n: 3, file: 'docs/03-erc20-openzeppelin.md', title: 'ERC-20 与 OpenZeppelin', short: 'ERC-20 与 OZ', min: 60, tests: 13,
      desc: '从零写 ERC-20，再用 OZ v5 组合生产级代币，掌握 Permit 签名与 SafeERC20。', tags: ['OZ v5', 'EIP-2612', 'USDT'] },
    { n: 4, file: 'docs/04-security.md', title: '合约安全基础', short: '合约安全', min: 60, tests: 5,
      desc: '亲眼看重入攻击掏空银行，再用 CEI + ReentrancyGuard 修好它；tx.origin 钓鱼演示。', tags: ['The DAO', 'ReentrancyGuard'] },
    { n: 5, file: 'docs/05-uniswap-v2.md', title: 'AMM：Uniswap V2', short: 'Uniswap V2', min: 75, tests: 14,
      desc: '恒定乘积、LP 份额、k 检查、闪电兑换与 TWAP，实现 getAmountOut 和 swap 核心。', tags: ['UniswapV2Pair', 'flash swap', 'TWAP'] },
    { n: 6, file: 'docs/06-lending.md', title: '借贷：Compound 与 Aave', short: '借贷协议', min: 75, tests: 15,
      desc: '拐点利率模型、借款指数、健康因子与清算，在 200 行迷你协议里全部实现。', tags: ['JumpRateModel', 'borrowIndex', '清算'] },
    { n: 7, file: 'docs/07-deploy-fork.md', title: '部署脚本与主网分叉测试', short: '部署与分叉测试', min: 35, tests: 4,
      desc: '用 forge script 部署到 anvil，在主网分叉上直接调用真实的 Uniswap 与 Aave。', tags: ['forge script', 'anvil', 'mainnet fork'] }
  ];
  var REPO = 'https://github.com/zealton/solidity-8h/blob/main/';

  var $ = function (s, el) { return (el || document).querySelector(s); };
  var view = $('#view'), toc = $('#toc'), nav = $('#nav'), crumbs = $('#crumbs');
  var cache = {};

  // ---------- 存储（可能不可用） ----------
  function load(key, fallback) {
    try { var v = localStorage.getItem(key); return v ? JSON.parse(v) : fallback; } catch (e) { return fallback; }
  }
  function save(key, val) { try { localStorage.setItem(key, JSON.stringify(val)); } catch (e) {} }
  var done = load('done', {});

  function fmtMin(m) {
    var h = Math.floor(m / 60), r = m % 60;
    return h ? (r ? h + ' h ' + r + ' min' : h + ' h') : r + ' min';
  }
  function esc(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function fetchText(path) {
    if (cache[path]) return Promise.resolve(cache[path]);
    return fetch(path).then(function (r) {
      if (!r.ok) throw new Error(r.status);
      return r.text();
    }).then(function (t) { cache[path] = t; return t; });
  }

  // ---------- 侧边栏 ----------
  function renderNav(active) {
    var html = '<div class="nav-label">开始</div>' +
      '<a class="nav-item' + (active === 'home' ? ' active' : '') + '" href="#/">' +
      '<span class="nav-num">⌂</span><span class="nav-title">课程首页</span></a>' +
      '<a class="nav-item' + (active === 'readme' ? ' active' : '') + '" href="#/readme">' +
      '<span class="nav-num">i</span><span class="nav-title">使用说明</span></a>' +
      '<div class="nav-label">章节 · 共 ' + fmtMin(CHAPTERS.reduce(function (a, c) { return a + c.min; }, 0)) + '</div>';
    CHAPTERS.forEach(function (c) {
      var cls = 'nav-item' + (active === c.n ? ' active' : '') + (done[c.n] ? ' done' : '');
      html += '<a class="' + cls + '" href="#/ch/' + c.n + '">' +
        '<span class="nav-num">' + (done[c.n] && active !== c.n ? '✓' : c.n) + '</span>' +
        '<span class="nav-title">' + esc(c.short) + '</span>' +
        '<span class="nav-time">' + c.min + "'</span></a>";
    });
    nav.innerHTML = html;
    var count = CHAPTERS.filter(function (c) { return done[c.n]; }).length;
    $('#progressText').textContent = count + ' / ' + CHAPTERS.length;
    $('#progressFill').style.width = (count / CHAPTERS.length * 100) + '%';
  }

  function setCrumbs(parts) {
    crumbs.innerHTML = parts.map(function (p, i) {
      if (i === parts.length - 1) return '<span class="current">' + esc(p.label) + '</span>';
      return '<a href="' + p.href + '">' + esc(p.label) + '</a><span class="sep">/</span>';
    }).join('');
  }

  // ---------- 首页 ----------
  function renderHome() {
    var total = CHAPTERS.reduce(function (a, c) { return a + c.min; }, 0);
    var tests = CHAPTERS.reduce(function (a, c) { return a + c.tests; }, 0);
    var count = CHAPTERS.filter(function (c) { return done[c.n]; }).length;
    var next = CHAPTERS.filter(function (c) { return !done[c.n]; })[0] || CHAPTERS[0];

    var cards = CHAPTERS.map(function (c) {
      return '<a class="card' + (done[c.n] ? ' done' : '') + '" href="#/ch/' + c.n + '">' +
        '<div class="card-top"><span class="card-num">' + String(c.n).padStart(2, '0') + '</span>' +
        '<span class="card-title">' + esc(c.title) + '</span>' +
        (done[c.n] ? '<span class="pill ok">已完成</span>' : '<span class="pill">' + c.min + ' min</span>') + '</div>' +
        '<p class="card-desc">' + esc(c.desc) + '</p>' +
        '<div class="card-tags">' + c.tags.map(function (t) { return '<span class="tag">' + esc(t) + '</span>'; }).join('') + '</div></a>';
    }).join('');

    view.innerHTML =
      '<section class="hero">' +
        '<span class="eyebrow"><b>Foundry</b>写给 CS 毕业生的 Web3 入门</span>' +
        '<h1>8 小时，从 EVM 到<br><span class="grad">Uniswap 与 Aave 的真实代码</span></h1>' +
        '<p>不讲“什么是变量”。每章一篇讲义、一份带 TODO 的练习合约、一组 Foundry 测试和小测验。填完 TODO，测试全绿，这一章就过关。</p>' +
        '<div class="hero-actions">' +
          '<a class="btn btn-primary" href="#/ch/' + next.n + '">' + (count ? '继续第 ' + next.n + ' 章' : '从第 0 章开始') +
            ' <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></a>' +
          '<a class="btn" href="https://github.com/zealton/solidity-8h" target="_blank" rel="noopener">查看代码仓库</a>' +
        '</div>' +
      '</section>' +
      '<div class="stats">' +
        stat('章节', CHAPTERS.length, '章', 'var(--blue-500)') +
        stat('学习时长', (total / 60).toFixed(1).replace('.0', ''), '小时', 'var(--violet-500)') +
        stat('Foundry 测试', tests, '个', 'var(--green-500)') +
        stat('已完成', count, '/ ' + CHAPTERS.length, 'var(--amber-500)') +
      '</div>' +
      '<div class="section-head"><h2>课程章节</h2><span>建议两个半天：上午 0–3 章，下午 4–7 章</span></div>' +
      '<div class="cards">' + cards + '</div>' +
      '<div class="steps">' +
        step('01', '安装 Foundry', '一行命令装好 forge、cast、anvil。', 'curl -L https://foundry.paradigm.xyz | bash\nfoundryup') +
        step('02', '安装依赖', '克隆仓库后安装 forge-std 与 OpenZeppelin。', 'git clone https://github.com/zealton/solidity-8h\ncd solidity-8h && ./setup.sh') +
        step('03', '跑第一章测试', '红了就去 src/ 搜索 TODO。', 'forge test --match-path "test/ch00/*" -vv') +
      '</div>';
    highlight(view);
    addCopyButtons(view);
    toc.innerHTML = '';
  }
  function stat(label, value, unit, color) {
    return '<div class="stat"><div class="stat-label"><span class="stat-dot" style="background:' + color + '"></span>' + label +
      '</div><div class="stat-value">' + value + '<small>' + unit + '</small></div></div>';
  }
  function step(n, title, text, code) {
    return '<div class="step"><div class="step-n">' + n + '</div><h3>' + title + '</h3><p>' + text +
      '</p><pre><code class="language-bash">' + esc(code) + '</code></pre></div>';
  }

  // ---------- Markdown ----------
  function rewriteHref(href) {
    if (!href || /^(https?:|mailto:|#)/.test(href)) return null;
    var m = href.match(/(?:^|\/)0(\d)-[\w-]+\.md(#.*)?$/);
    if (m) return '#/ch/' + m[1];
    if (/README\.md$/.test(href)) return '#/readme';
    return REPO + href.replace(/^\.\.\//, '').replace(/^\.\//, '');
  }

  function renderMarkdown(md) {
    var html = marked.parse(md, { gfm: true });
    var box = document.createElement('div');
    box.className = 'md';
    box.innerHTML = html;

    box.querySelectorAll('a[href]').forEach(function (a) {
      var href = a.getAttribute('href');
      var r = rewriteHref(href);
      if (r) a.setAttribute('href', r);
      if (/^https?:/.test(a.getAttribute('href'))) { a.target = '_blank'; a.rel = 'noopener'; }
    });
    box.querySelectorAll('table').forEach(function (t) {
      var w = document.createElement('div');
      w.className = 'table-wrap';
      t.parentNode.insertBefore(w, t);
      w.appendChild(t);
    });
    var i = 0;
    box.querySelectorAll('h2, h3').forEach(function (h) {
      h.id = 'sec-' + (i++);
      if (h.tagName === 'H2' && /小测验/.test(h.textContent)) h.classList.add('quiz');
    });
    box.querySelectorAll('pre code:not([class])').forEach(function (c) { c.className = 'language-none'; });
    box.querySelectorAll('pre code.language-sol').forEach(function (c) { c.className = 'language-solidity'; });
    return box;
  }

  function highlight(root) {
    if (window.Prism) root.querySelectorAll('pre code').forEach(function (c) { Prism.highlightElement(c); });
  }
  function addCopyButtons(root) {
    root.querySelectorAll('pre').forEach(function (pre) {
      var b = document.createElement('button');
      b.className = 'copy-btn';
      b.type = 'button';
      b.textContent = '复制';
      b.addEventListener('click', function () {
        var text = pre.querySelector('code').innerText;
        (navigator.clipboard ? navigator.clipboard.writeText(text) : Promise.reject()).then(function () {
          b.textContent = '已复制';
        }, function () { b.textContent = '复制失败'; });
        setTimeout(function () { b.textContent = '复制'; }, 1400);
      });
      pre.appendChild(b);
    });
  }

  function buildToc(box) {
    var hs = box.querySelectorAll('h2, h3');
    if (hs.length < 2) { toc.innerHTML = ''; return; }
    var html = '<div class="toc-title">本页内容</div>';
    hs.forEach(function (h) {
      html += '<a href="#' + h.id + '" data-id="' + h.id + '" style="padding-left:' + (h.tagName === 'H3' ? 22 : 10) + 'px">' +
        esc(h.textContent) + '</a>';
    });
    toc.innerHTML = html;
    toc.querySelectorAll('a').forEach(function (a) {
      a.addEventListener('click', function (e) {
        e.preventDefault();
        var el = document.getElementById(a.dataset.id);
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    });
    if (!('IntersectionObserver' in window)) return;
    var obs = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) {
          toc.querySelectorAll('a').forEach(function (a) { a.classList.toggle('active', a.dataset.id === en.target.id); });
        }
      });
    }, { rootMargin: '-80px 0px -70% 0px' });
    hs.forEach(function (h) { obs.observe(h); });
  }

  // ---------- 章节页 ----------
  function renderDoc(path, chapter, scrollTo) {
    view.innerHTML = '<div class="loading">加载中…</div>';
    toc.innerHTML = '';
    fetchText(path).then(function (md) {
      var box = renderMarkdown(md);
      var title = chapter ? chapter.title : '使用说明';
      var head = document.createElement('div');
      head.className = 'doc-head';
      head.innerHTML = '<div class="doc-meta">' +
        (chapter
          ? '<span class="pill">第 ' + chapter.n + ' 章</span><span class="pill">' + chapter.min + ' 分钟</span>' +
            '<span class="pill">' + chapter.tests + ' 个测试</span>' +
            '<button class="done-toggle' + (done[chapter.n] ? ' on' : '') + '" type="button" id="doneBtn">' +
            (done[chapter.n] ? '✓ 已完成' : '标记为已完成') + '</button>'
          : '<span class="pill">README</span>') +
        '</div><h1>' + esc(title) + '</h1>';

      view.innerHTML = '';
      view.appendChild(head);
      view.appendChild(box);
      if (chapter) view.appendChild(pager(chapter.n));
      highlight(box);
      addCopyButtons(box);
      buildToc(box);

      var btn = $('#doneBtn');
      if (btn) btn.addEventListener('click', function () {
        done[chapter.n] = !done[chapter.n];
        save('done', done);
        btn.classList.toggle('on', !!done[chapter.n]);
        btn.textContent = done[chapter.n] ? '✓ 已完成' : '标记为已完成';
        renderNav(chapter.n);
      });

      if (scrollTo) {
        var target = findText(box, scrollTo);
        if (target) setTimeout(function () { target.scrollIntoView({ block: 'center' }); flash(target); }, 30);
      }
    }).catch(function () {
      view.innerHTML = '<div class="loading">讲义加载失败，请刷新重试。</div>';
    });
  }
  function pager(n) {
    var prev = CHAPTERS[n - 1], next = CHAPTERS[n + 1];
    var el = document.createElement('nav');
    el.className = 'pager';
    el.innerHTML =
      (prev ? '<a href="#/ch/' + prev.n + '"><small>← 上一章</small><span>' + esc(prev.title) + '</span></a>' : '<span></span>') +
      (next ? '<a class="next" href="#/ch/' + next.n + '"><small>下一章 →</small><span>' + esc(next.title) + '</span></a>' : '');
    return el;
  }
  function findText(root, q) {
    var lower = q.toLowerCase();
    var nodes = root.querySelectorAll('h2, h3, p, li, td, pre, blockquote');
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].textContent.toLowerCase().indexOf(lower) >= 0) return nodes[i];
    }
    return null;
  }
  function flash(el) {
    el.style.transition = 'background 0.6s';
    el.style.background = 'var(--accent-soft)';
    el.style.borderRadius = '8px';
    setTimeout(function () { el.style.background = ''; }, 1400);
  }

  // ---------- 路由 ----------
  var pendingScroll = null;
  function route() {
    var h = location.hash || '#/';
    closeSidebar();
    if (/^#sec-/.test(h)) return; // 页内锚点
    var m = h.match(/^#\/ch\/(\d)/);
    if (m && CHAPTERS[+m[1]]) {
      var c = CHAPTERS[+m[1]];
      renderNav(c.n);
      setCrumbs([{ label: '课程', href: '#/' }, { label: '第 ' + c.n + ' 章 · ' + c.title }]);
      document.title = c.title + ' · Solidity 8 小时入门';
      renderDoc(c.file, c, pendingScroll);
    } else if (h.indexOf('#/readme') === 0) {
      renderNav('readme');
      setCrumbs([{ label: '课程', href: '#/' }, { label: '使用说明' }]);
      document.title = '使用说明 · Solidity 8 小时入门';
      renderDoc('README.md', null, pendingScroll);
    } else {
      renderNav('home');
      setCrumbs([{ label: '课程', href: '#/' }, { label: '首页' }]);
      document.title = 'Solidity 8 小时入门';
      renderHome();
    }
    pendingScroll = null;
    window.scrollTo(0, 0);
  }
  window.addEventListener('hashchange', route);

  // ---------- 主题 ----------
  $('#themeBtn').addEventListener('click', function () {
    var dark = !document.documentElement.classList.contains('dark');
    document.documentElement.classList.toggle('dark', dark);
    try { localStorage.setItem('theme', dark ? 'dark' : 'light'); } catch (e) {}
  });

  // ---------- 移动端侧边栏 ----------
  var sidebar = $('#sidebar'), scrim = $('#scrim');
  function closeSidebar() { sidebar.classList.remove('open'); scrim.classList.remove('show'); }
  $('#menuBtn').addEventListener('click', function () { sidebar.classList.add('open'); scrim.classList.add('show'); });
  scrim.addEventListener('click', closeSidebar);

  // ---------- 搜索 ----------
  var overlay = $('#searchOverlay'), input = $('#searchInput'), results = $('#searchResults');
  var index = null, sel = 0, hits = [];

  function buildIndex() {
    if (index) return Promise.resolve(index);
    var docs = CHAPTERS.map(function (c) { return { path: c.file, ch: c }; }).concat([{ path: 'README.md', ch: null }]);
    return Promise.all(docs.map(function (d) {
      return fetchText(d.path).then(function (md) {
        var out = [], section = d.ch ? d.ch.title : '使用说明', fence = false;
        md.split('\n').forEach(function (line) {
          if (/^\s*(>\s*)?```/.test(line)) { fence = !fence; return; }
          var hm = !fence && line.match(/^#{1,3}\s+(.*)/);
          if (hm) { section = hm[1]; out.push({ doc: d, section: section, text: section, isHeading: true }); return; }
          var text = line.replace(/[`*>|#]/g, ' ').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/<[^>]+>/g, '').trim();
          if (text.length > 1) out.push({ doc: d, section: section, text: text });
        });
        out.push({ doc: d, section: d.ch ? d.ch.title : '使用说明', text: d.ch ? d.ch.title + ' ' + d.ch.desc : '使用说明', isTitle: true });
        return out;
      }, function () { return []; });
    })).then(function (parts) { index = [].concat.apply([], parts); return index; });
  }

  function openSearch() {
    overlay.hidden = false;
    input.value = '';
    renderResults('');
    setTimeout(function () { input.focus(); }, 0);
    buildIndex().then(function () { renderResults(input.value); });
  }
  function closeSearch() { overlay.hidden = true; }

  function renderResults(q) {
    q = q.trim();
    if (!q) {
      hits = CHAPTERS.map(function (c) { return { doc: { ch: c, path: c.file }, section: c.title, text: c.desc }; });
    } else if (!index) {
      results.innerHTML = '<div class="search-empty">正在建立索引…</div>';
      return;
    } else {
      var lq = q.toLowerCase(), seen = {};
      // 标题命中排前面，其次是正文命中；同一段落去重
      var heads = [], body = [];
      index.forEach(function (e) {
        if (e.text.toLowerCase().indexOf(lq) < 0) return;
        var key = e.doc.path + '|' + e.section + '|' + e.text;
        if (seen[key]) return;
        seen[key] = 1;
        (e.isHeading || e.isTitle ? heads : body).push(e);
      });
      hits = heads.concat(body).slice(0, 30);
    }
    sel = 0;
    if (!hits.length) { results.innerHTML = '<div class="search-empty">没有找到“' + esc(q) + '”</div>'; return; }
    results.innerHTML = hits.map(function (e, i) {
      var label = e.doc.ch ? '第 ' + e.doc.ch.n + ' 章' : 'README';
      return '<a class="result' + (i === 0 ? ' sel' : '') + '" href="' + hrefFor(e) + '" data-i="' + i + '">' +
        '<div class="result-top"><span class="pill">' + label + '</span><b>' + mark(e.section, q) + '</b></div>' +
        (e.isHeading ? '' : '<div class="result-snippet">' + mark(snippet(e.text, q), q) + '</div>') + '</a>';
    }).join('');
  }
  function hrefFor(e) { return e.doc.ch ? '#/ch/' + e.doc.ch.n : '#/readme'; }
  function snippet(text, q) {
    if (!q) return text;
    var i = text.toLowerCase().indexOf(q.toLowerCase());
    if (i < 30) return text;
    return '…' + text.slice(i - 24);
  }
  function mark(text, q) {
    var s = esc(text);
    if (!q) return s;
    var eq = esc(q).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return s.replace(new RegExp(eq, 'ig'), function (m) { return '<mark>' + m + '</mark>'; });
  }
  function go(i) {
    var e = hits[i];
    if (!e) return;
    var q = input.value.trim();
    closeSearch();
    var target = hrefFor(e);
    pendingScroll = q && !e.isTitle ? (e.isHeading ? e.section : q) : null;
    if (location.hash === target) route(); else location.hash = target;
  }

  results.addEventListener('click', function (ev) {
    var a = ev.target.closest('.result');
    if (!a) return;
    ev.preventDefault();
    go(+a.dataset.i);
  });
  input.addEventListener('input', function () { renderResults(input.value); });
  input.addEventListener('keydown', function (ev) {
    var items = results.querySelectorAll('.result');
    if (ev.key === 'ArrowDown' || ev.key === 'ArrowUp') {
      ev.preventDefault();
      if (!items.length) return;
      sel = (sel + (ev.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
      items.forEach(function (it, i) { it.classList.toggle('sel', i === sel); });
      items[sel].scrollIntoView({ block: 'nearest' });
    } else if (ev.key === 'Enter') {
      ev.preventDefault();
      go(sel);
    }
  });
  overlay.addEventListener('click', function (ev) { if (ev.target === overlay) closeSearch(); });
  $('#searchOpen').addEventListener('click', openSearch);
  $('#searchOpen2').addEventListener('click', openSearch);
  document.addEventListener('keydown', function (ev) {
    if ((ev.metaKey || ev.ctrlKey) && ev.key.toLowerCase() === 'k') { ev.preventDefault(); overlay.hidden ? openSearch() : closeSearch(); }
    else if (ev.key === 'Escape' && !overlay.hidden) closeSearch();
    else if (ev.key === '/' && overlay.hidden && !/input|textarea/i.test(document.activeElement.tagName)) { ev.preventDefault(); openSearch(); }
  });

  route();
})();
