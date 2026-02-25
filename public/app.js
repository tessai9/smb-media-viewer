(function () {
  'use strict';

  var grid = document.querySelector('.grid');
  if (!grid) return;

  var path = grid.dataset.path || '';
  var offset = parseInt(grid.dataset.offset) || 0;
  var busy = false, exhausted = false;

  function encodePath(path) {
    return path.split('/').map(encodeURIComponent).join('/');
  }

  function buildCard(e) {
    var a = document.createElement('a');
    a.className = e.is_dir ? 'card card--dir' : 'card';
    a.href = e.is_dir ? '/browse/' + encodePath(e.path) : '/view/' + encodePath(e.path);
    if (!e.is_dir) a.dataset.mediaType = e.media_type;
    var inner = e.is_dir
      ? '<div class="thumb thumb--dir"></div>'
      : '<img src="" data-src="/thumbnail/' + encodePath(e.path) + '" alt="">';
    a.innerHTML = inner + '<span class="name">' + e.name + '</span>';
    return a;
  }

  function loadMore() {
    if (busy || exhausted) return;
    busy = true;
    var sort = grid.dataset.sort || 'name';
    var order = grid.dataset.order || 'asc';
    var url = '/api/files/' + path + '?offset=' + offset + '&limit=50&sort=' + sort + '&order=' + order;
    fetch(url)
      .then(function (r) { return r.json(); })
      .then(function (items) {
        if (!items.length) { exhausted = true; busy = false; return; }
        var sentinel = document.getElementById('sentinel');
        items.forEach(function (e) {
          var card = buildCard(e);
          grid.insertBefore(card, sentinel);
          if (!e.is_dir && imgIO) imgIO.observe(card.querySelector('img'));
        });
        offset += items.length;
        grid.dataset.offset = offset;
        busy = false;
      })
      .catch(function () { busy = false; });
  }

  var imgIO = null;

  if (typeof IntersectionObserver !== 'undefined') {
    imgIO = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        var img = entry.target;
        if (entry.isIntersecting) { img.src = img.dataset.src || ''; }
        else { img.src = ''; }
      });
    }, { rootMargin: '200px' });

    document.querySelectorAll('img[data-src]').forEach(function (img) {
      imgIO.observe(img);
    });

    var sentinel = document.getElementById('sentinel');
    if (sentinel) {
      new IntersectionObserver(function (entries) {
        if (entries[0].isIntersecting) loadMore();
      }, { rootMargin: '400px' }).observe(sentinel);
    }
  } else {
    document.querySelectorAll('img[data-src]').forEach(function (img) {
      img.src = img.dataset.src || '';
    });
  }

  var overlay = document.createElement('div');
  overlay.id = 'overlay';
  overlay.hidden = true;
  overlay.innerHTML = '<img id="overlay-img" src="" alt=""><p id="overlay-name"></p>'
    + '<button id="overlay-close">\u00d7</button>'
    + '<button id="overlay-prev">\u2039</button>'
    + '<button id="overlay-next">\u203a</button>';
  document.body.appendChild(overlay);

  var b = document.body;
  var oImg = document.getElementById('overlay-img');
  var oName = document.getElementById('overlay-name');
  var oClose = document.getElementById('overlay-close');
  var oOpen = false, oCur = null, oSY = 0;

  function openOverlay(c) {
    oSY = window.scrollY; oCur = c; oOpen = true;
    oImg.src = '';
    oImg.src = c.href.replace('/view/', '/raw/');
    oName.textContent = c.lastElementChild.textContent;
    b.classList.add('overlay-open');
    overlay.hidden = false;
    history.pushState(0, 0, c.href);
    updateNavButtons();
  }

  function closeOverlay(fp) {
    oOpen = false; overlay.hidden = true; oImg.src = '';
    b.classList.remove('overlay-open');
    window.scrollTo(0, oSY);
    if (!fp) history.back();
  }

  function updateNavButtons() {}

  oClose.addEventListener('click', function() { closeOverlay(0); });
  overlay.addEventListener('click', function(e) { if (e.target === overlay) closeOverlay(0); });
  window.addEventListener('popstate', function() { if (oOpen) closeOverlay(1); });

  grid.addEventListener('click', function(e) {
    var card = e.target.closest('.card');
    if (!card || card.classList.contains('card--dir')) return;
    var mt = card.dataset.mediaType;
    if (mt === 'image') { e.preventDefault(); openOverlay(card); }
    else if (mt === 'video') { e.preventDefault(); window.open(card.href, '_blank'); }
  });
}());
