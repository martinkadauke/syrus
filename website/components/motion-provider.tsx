"use client";

import { MotionConfig } from "motion/react";
import type { ReactNode } from "react";

// reducedMotion="user": Motion suppresses transform animations for
// prefers-reduced-motion users but still runs opacity, so reveal-animated
// content always becomes visible. Crucially, the rendered tree is identical on
// server and client — branching on useReducedMotion() during hydration left
// the SSR opacity:0 styles permanently stuck for reduced-motion users.
export function MotionProvider({ children }: { children: ReactNode }) {
  return <MotionConfig reducedMotion="user">{children}</MotionConfig>;
}
