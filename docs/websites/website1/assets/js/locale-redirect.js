(function () {
  "use strict";

  var SUPPORTED = ["en", "ru", "de", "fr", "es"];
  var DEFAULT = "en";
  var STORAGE_KEY = "beardy-site-lang";

  function normalize(lang) {
    if (!lang) return null;
    var base = lang.toLowerCase().split("-")[0];
    return SUPPORTED.indexOf(base) >= 0 ? base : null;
  }

  function fromNavigator() {
    if (navigator.languages && navigator.languages.length) {
      for (var i = 0; i < navigator.languages.length; i++) {
        var m = normalize(navigator.languages[i]);
        if (m) return m;
      }
    }
    return normalize(navigator.language);
  }

  function stored() {
    try {
      return normalize(localStorage.getItem(STORAGE_KEY));
    } catch (e) {
      return null;
    }
  }

  function save(lang) {
    try {
      localStorage.setItem(STORAGE_KEY, lang);
    } catch (e) { /* ignore */ }
  }

  function redirect() {
    var params = new URLSearchParams(window.location.search);
    var q = normalize(params.get("lang"));
    if (q) {
      save(q);
      window.location.replace("./" + q + "/");
      return;
    }

    var saved = stored();
    var lang = saved || fromNavigator() || DEFAULT;
    save(lang);
    window.location.replace("./" + lang + "/");
  }

  redirect();
})();
