import type { AnchorHTMLAttributes, ReactNode } from "react";

type Variant = "primary" | "secondary" | "ghost";
type Size = "md" | "lg";

const sizes: Record<Size, string> = {
  md: "h-10 px-4 text-sm gap-2",
  lg: "h-12 px-5 text-[0.95rem] gap-2.5",
};

const variants: Record<Variant, string> = {
  primary:
    "clay-gradient text-on-accent font-semibold shadow-[0_1px_0_rgba(255,255,255,0.25)_inset,0_10px_30px_-12px_var(--accent-shadow)] hover:brightness-[1.06] hover:-translate-y-0.5",
  secondary:
    "hairline bg-[color-mix(in_oklab,var(--color-cream)_5%,transparent)] text-cream font-medium hover:bg-[color-mix(in_oklab,var(--color-cream)_10%,transparent)] hover:-translate-y-0.5",
  ghost:
    "text-cream-dim font-medium hover:text-cream hover:bg-[color-mix(in_oklab,var(--color-cream)_6%,transparent)]",
};

type ButtonLinkProps = AnchorHTMLAttributes<HTMLAnchorElement> & {
  variant?: Variant;
  size?: Size;
  children: ReactNode;
};

export function ButtonLink({
  variant = "primary",
  size = "md",
  className = "",
  children,
  ...props
}: ButtonLinkProps) {
  return (
    <a
      className={`group inline-flex items-center justify-center rounded-full transition-all duration-200 ease-out ${sizes[size]} ${variants[variant]} ${className}`}
      {...props}
    >
      {children}
    </a>
  );
}
