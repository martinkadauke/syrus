import type { ReactNode } from "react";
import { Nav } from "./nav";
import { Footer } from "./footer";

export function LegalShell({
  title,
  updated,
  children,
}: {
  title: string;
  updated?: string;
  children: ReactNode;
}) {
  return (
    <>
      <Nav />
      <main id="main" className="wrap max-w-3xl pt-32 pb-24">
        <a
          href="/"
          className="text-[0.85rem] text-cream-dim transition-colors hover:text-cream"
        >
          ← Back to home
        </a>
        <h1 className="mt-6 text-balance text-4xl font-semibold tracking-tight text-cream">
          {title}
        </h1>
        {updated ? (
          <p className="mt-2 text-[0.85rem] text-cream-faint">
            Last updated: {updated}
          </p>
        ) : null}
        <div className="legal-prose mt-8">{children}</div>
      </main>
      <Footer />
    </>
  );
}
