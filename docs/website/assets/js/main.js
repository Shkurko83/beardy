(function () {
  "use strict";

  function initMobileNav() {
    var toggle = document.getElementById("menu-toggle");
    var nav = document.getElementById("mobile-nav");
    var overlay = document.getElementById("mobile-nav-overlay");
    if (!toggle || !nav) return;

    function setOpen(open) {
      nav.classList.toggle("is-open", open);
      if (overlay) overlay.classList.toggle("is-open", open);
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
      document.body.style.overflow = open ? "hidden" : "";
    }

    toggle.addEventListener("click", function () {
      setOpen(!nav.classList.contains("is-open"));
    });

    if (overlay) {
      overlay.addEventListener("click", function () {
        setOpen(false);
      });
    }

    nav.querySelectorAll("a").forEach(function (link) {
      link.addEventListener("click", function () {
        setOpen(false);
      });
    });
  }

  function initLangMenu() {
    var btn = document.getElementById("lang-toggle");
    var menu = document.getElementById("lang-dropdown");
    if (!btn || !menu) return;

    function setOpen(open) {
      menu.classList.toggle("is-open", open);
      btn.setAttribute("aria-expanded", open ? "true" : "false");
    }

    btn.addEventListener("click", function (e) {
      e.stopPropagation();
      setOpen(!menu.classList.contains("is-open"));
    });

    document.addEventListener("click", function () {
      setOpen(false);
    });

    menu.addEventListener("click", function (e) {
      e.stopPropagation();
    });
  }

  function initReveal() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      document.querySelectorAll(".reveal").forEach(function (el) {
        el.classList.add("is-visible");
      });
      return;
    }

    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );

    document.querySelectorAll(".reveal").forEach(function (el) {
      observer.observe(el);
    });
  }

  function initYear() {
    document.querySelectorAll("[data-year]").forEach(function (el) {
      el.textContent = String(new Date().getFullYear());
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    initMobileNav();
    initLangMenu();
    initReveal();
    initYear();
  });
})();
