import type { ReactNode } from "react";
import { Reveal } from "./reveal";

export function SectionHeader({
  eyebrow,
  title,
  subtitle,
  align = "center",
}: {
  eyebrow: string;
  title: ReactNode;
  subtitle?: ReactNode;
  align?: "center" | "left";
}) {
  const alignment =
    align === "center" ? "mx-auto max-w-2xl text-center" : "max-w-2xl";
  return (
    <Reveal className={alignment}>
      <p className="inline-flex items-center gap-2 font-mono text-[0.72rem] uppercase tracking-[0.18em] text-clay">
        <span className="size-1 rounded-full bg-clay" />
        {eyebrow}
      </p>
      <h2 className="mt-4 text-balance text-3xl font-semibold leading-[1.1] tracking-[-0.02em] text-cream sm:text-[2.6rem]">
        {title}
      </h2>
      {subtitle ? (
        <p className="mt-4 text-pretty text-[1.02rem] leading-relaxed text-cream-dim">
          {subtitle}
        </p>
      ) : null}
    </Reveal>
  );
}
