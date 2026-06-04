(function () {
  "use strict";
  var STORAGE_KEY = "beardy-site-lang";

  function save(lang) {
    try {
      localStorage.setItem(STORAGE_KEY, lang);
    } catch (e) { /* ignore */ }
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("[data-lang]").forEach(function (link) {
      link.addEventListener("click", function () {
        var lang = link.getAttribute("data-lang");
        if (lang) save(lang);
      });
    });
  });
})();
