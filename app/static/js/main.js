// Campus Lost and Found Portal — main.js  (Phase 1)
// Provides client-side enhancements; the application is fully functional
// without JavaScript (progressive enhancement).

console.log("Campus Lost and Found Portal — Phase 1 loaded.");

// ── Auto-dismiss flash messages after 6 seconds ───────────────────────────────
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll(".flash").forEach((el) => {
    setTimeout(() => {
      el.style.transition = "opacity 0.5s";
      el.style.opacity = "0";
      setTimeout(() => el.remove(), 500);
    }, 6000);
  });
});
