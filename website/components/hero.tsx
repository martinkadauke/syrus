"use client";

import { motion } from "motion/react";
import { ButtonLink } from "./button";
import { DownloadCTA } from "./download-cta";
import { ScreenshotFrame } from "./screenshot-frame";
import { ArrowRight } from "./icons";
import { hero, site } from "../lib/site";

const ease = [0.22, 1, 0.36, 1] as const;

const chips = [
  "More shipped per sprint",
  "Human review on every merge",
  "Epics, tickets & cost, fully tracked",
];

export function Hero({
  desktopSrc = null,
  mobileSrc = null,
}: {
  desktopSrc?: string | null;
  mobileSrc?: string | null;
}) {
  // Reduced-motion is handled globally by <MotionProvider> — no branching here
  // (a divergent hydration tree left SSR opacity:0 stuck for those users).
  const container = {
    hidden: {},
    show: { transition: { staggerChildren: 0.12, delayChildren: 0.05 } },
  };
  const item = {
    hidden: { opacity: 0, y: 24 },
    show: { opacity: 1, y: 0, transition: { duration: 0.75, ease } },
  };

  return (
    <section
      id="top"
      className="grain relative overflow-hidden pt-28 pb-16 sm:pt-36 sm:pb-24"
    >
      {/* ambient glow */}
      <div aria-hidden className="absolute inset-0 -z-0">
        <div
          className="aurora animate-float-slow left-1/2 top-[-10%] h-[520px] w-[720px] -translate-x-1/2"
          style={{
            background:
              "radial-gradient(closest-side, var(--aurora-a), transparent)",
          }}
        />
        <div
          className="aurora left-[8%] top-[30%] h-[360px] w-[360px]"
          style={{
            background:
              "radial-gradient(closest-side, var(--aurora-b), transparent)",
          }}
        />
        <div
          className="aurora right-[6%] top-[8%] h-[320px] w-[320px]"
          style={{
            background:
              "radial-gradient(closest-side, var(--aurora-c), transparent)",
          }}
        />
      </div>

      <div className="wrap relative z-10">
        <motion.div
          data-reveal
          variants={container}
          initial="hidden"
          animate="show"
          className="mx-auto max-w-3xl text-center"
        >
          <motion.div variants={item}>
            <span className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.03] px-3.5 py-1.5 text-[0.78rem] text-cream-dim backdrop-blur">
              <span className="size-1.5 rounded-full clay-gradient" />
              {hero.eyebrow}
            </span>
          </motion.div>

          <motion.h1
            variants={item}
            className="mt-7 text-balance text-[2.6rem] font-semibold leading-[1.04] tracking-[-0.02em] sm:text-6xl"
          >
            <span className="text-cream">{hero.titleLead}</span>
            <br />
            <span className="clay-text">{hero.titleAccent}</span>
          </motion.h1>

          <motion.p
            variants={item}
            className="mx-auto mt-6 max-w-2xl text-pretty text-[1.02rem] leading-relaxed text-cream-dim sm:text-[1.12rem]"
          >
            {hero.subtitle}
          </motion.p>

          <motion.div
            variants={item}
            className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row sm:items-start"
          >
            <DownloadCTA size="lg" />
            <ButtonLink
              href="/#demo"
              variant="secondary"
              size="lg"
              className="w-full sm:w-auto"
            >
              Request a demo
              <ArrowRight className="size-4 transition-transform duration-200 group-hover:translate-x-0.5" />
            </ButtonLink>
          </motion.div>

          <motion.div
            variants={item}
            className="mt-6 flex flex-wrap items-center justify-center gap-x-5 gap-y-2 text-[0.8rem] text-cream-faint"
          >
            {chips.map((c) => (
              <span key={c} className="inline-flex items-center gap-1.5">
                <span className="size-1 rounded-full bg-clay" />
                {c}
              </span>
            ))}
          </motion.div>
        </motion.div>

        {/* product shot */}
        <motion.div
          data-reveal
          initial={{ opacity: 0, y: 40, scale: 0.98 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          transition={{ duration: 0.9, delay: 0.4, ease }}
          className="mx-auto mt-16 max-w-5xl"
        >
          <ScreenshotFrame desktopSrc={desktopSrc} mobileSrc={mobileSrc} />
          <p className="mt-3 text-center font-serif text-[0.95rem] italic text-cream-faint">
            {site.tagline}{" "}
            <span className="not-italic">
              {site.taglineTranslation} {site.taglineAttribution}
            </span>
          </p>
        </motion.div>
      </div>
    </section>
  );
}
