(function () {
  "use strict";

  var STORAGE_KEY = "beardy-site-theme";
  var root = document.documentElement;

  function systemTheme() {
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  function applyTheme(theme) {
    if (theme === "light" || theme === "dark") {
      root.setAttribute("data-theme", theme);
    } else {
      root.removeAttribute("data-theme");
    }
    updateToggleLabel();
    syncScreenshotTabs();
  }

  function storedTheme() {
    try {
      return localStorage.getItem(STORAGE_KEY);
    } catch (e) {
      return null;
    }
  }

  function saveTheme(theme) {
    try {
      if (theme) localStorage.setItem(STORAGE_KEY, theme);
      else localStorage.removeItem(STORAGE_KEY);
    } catch (e) { /* private mode */ }
  }

  function effectiveTheme() {
    var stored = storedTheme();
    if (stored === "light" || stored === "dark") return stored;
    return systemTheme();
  }

  function updateToggleLabel() {
    var btn = document.getElementById("theme-toggle");
    if (!btn) return;
    var stored = storedTheme();
    var label =
      stored === "light"
        ? "Light"
        : stored === "dark"
          ? "Dark"
          : "System";
    btn.setAttribute("aria-label", "Theme: " + label);
    btn.setAttribute("title", label);
  }

  function syncScreenshotTabs() {
    var theme = effectiveTheme();
    document.querySelectorAll("[data-shot-group]").forEach(function (group) {
      var light = group.querySelector('[data-shot-variant="light"]');
      var dark = group.querySelector('[data-shot-variant="dark"]');
      if (!light || !dark) return;
      var showDark = theme === "dark";
      light.classList.toggle("is-active", !showDark);
      dark.classList.toggle("is-active", showDark);
      group.querySelectorAll(".shot-theme-tab").forEach(function (tab) {
        var v = tab.getAttribute("data-shot-tab");
        tab.classList.toggle("is-active", v === (showDark ? "dark" : "light"));
        tab.setAttribute("aria-selected", v === (showDark ? "dark" : "light") ? "true" : "false");
      });
    });
  }

  function cycleTheme() {
    var stored = storedTheme();
    var next;
    if (!stored) next = "light";
    else if (stored === "light") next = "dark";
    else if (stored === "dark") next = null;
    else next = null;
    saveTheme(next);
    applyTheme(next);
  }

  function initScreenshotTabs() {
    document.querySelectorAll(".shot-theme-tab").forEach(function (tab) {
      tab.addEventListener("click", function () {
        var variant = tab.getAttribute("data-shot-tab");
        var group = tab.closest("[data-shot-group]");
        if (!group) return;
        group.querySelectorAll(".shot-variant").forEach(function (el) {
          el.classList.toggle("is-active", el.getAttribute("data-shot-variant") === variant);
        });
        group.querySelectorAll(".shot-theme-tab").forEach(function (t) {
          var v = t.getAttribute("data-shot-tab");
          t.classList.toggle("is-active", v === variant);
          t.setAttribute("aria-selected", v === variant ? "true" : "false");
        });
      });
    });
    syncScreenshotTabs();
  }

  applyTheme(storedTheme());

  var mq = window.matchMedia("(prefers-color-scheme: dark)");
  mq.addEventListener("change", function () {
    if (!storedTheme()) {
      applyTheme(null);
      syncScreenshotTabs();
    }
  });

  document.addEventListener("DOMContentLoaded", function () {
    var btn = document.getElementById("theme-toggle");
    if (btn) btn.addEventListener("click", cycleTheme);
    initScreenshotTabs();
  });

  window.BeardyTheme = {
    effective: effectiveTheme,
    apply: applyTheme,
    syncScreenshots: syncScreenshotTabs,
  };
})();
