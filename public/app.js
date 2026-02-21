(function () {
  'use strict';

  var grid = document.querySelector('.grid');
  if (!grid) return;

  var path = grid.dataset.path || '';
  var offset = parseInt(grid.dataset.offset) || 0;
  var busy = false, exhausted = false;

  function buildCard(e) {
    var a = document.createElement('a');
    a.className = e.is_dir ? 'card card--dir' : 'card';
    a.href = e.is_dir ? '/browse/' + e.path : '/view/' + e.path;
    var inner = e.is_dir
      ? '<div class="thumb thumb--dir"></div>'
      : '<img src="" data-src="/thumbnail/' + e.path + '" alt="">';
    a.innerHTML = inner + '<span class="name">' + e.name + '</span>';
    return a;
  }

  function loadMore() {
    if (busy || exhausted) return;
    busy = true;
    var url = '/api/files/' + path + '?offset=' + offset + '&limit=50';
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
}());
