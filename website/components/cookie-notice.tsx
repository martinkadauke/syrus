"use client";

import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "motion/react";

const KEY = "syrus-cookie-ack";

// Minimal, non-blocking transparency notice. The site sets no tracking/ad
// cookies and no third-party storage — only functional first-party storage
// (theme choice) — so an "accept/reject" consent wall isn't required; this is
// honest disclosure with a link to the privacy policy.
export function CookieNotice() {
  const [show, setShow] = useState(false);

  useEffect(() => {
    try {
      if (!localStorage.getItem(KEY)) setShow(true);
    } catch {
      setShow(true);
    }
  }, []);

  // While visible, reserve scroll room so the notice can't cover page-bottom
  // content (e.g. the footer theme toggle).
  useEffect(() => {
    if (!show) return;
    const prev = document.body.style.paddingBottom;
    document.body.style.paddingBottom = "110px";
    return () => {
      document.body.style.paddingBottom = prev;
    };
  }, [show]);

  function dismiss() {
    try {
      localStorage.setItem(KEY, "1");
    } catch {
      /* ignore */
    }
    setShow(false);
  }

  return (
    <AnimatePresence>
      {show && (
        <motion.div
          key="cookie"
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 24 }}
          transition={{ duration: 0.4, ease: [0.22, 1, 0.36, 1] }}
          className="pointer-events-none fixed inset-x-0 bottom-0 z-[60] px-4 pb-4"
        >
          <div
            role="region"
            aria-label="Cookie notice"
            className="pointer-events-auto mx-auto flex max-w-2xl flex-col gap-3 rounded-xl border border-white/10 bg-[color-mix(in_oklab,var(--color-ink-soft)_90%,transparent)] p-4 shadow-[0_20px_60px_-20px_rgba(0,0,0,0.85)] backdrop-blur-xl sm:flex-row sm:items-center sm:gap-4"
          >
            <p className="text-[0.85rem] leading-relaxed text-cream-dim">
              This site uses only essential, first-party browser storage to
              remember your preferences (like your theme). No tracking, no ads,
              no third parties.{" "}
              <a
                href="/privacy"
                className="text-clay underline underline-offset-2 hover:text-clay-bright"
              >
                Privacy
              </a>
              {" · "}
              <a
                href="/impressum"
                className="text-clay underline underline-offset-2 hover:text-clay-bright"
              >
                Impressum
              </a>
            </p>
            <button
              type="button"
              onClick={dismiss}
              className="shrink-0 rounded-full clay-gradient px-4 py-2 text-[0.82rem] font-semibold text-on-accent transition hover:brightness-[1.06]"
            >
              Got it
            </button>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
