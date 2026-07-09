export function Logo({ className = "" }: { className?: string }) {
  return (
    <span className={`inline-flex items-center gap-2 ${className}`}>
      <img
        src="/syrus-icon.png"
        alt=""
        aria-hidden="true"
        width={24}
        height={24}
        className="h-6 w-6 shrink-0 rounded"
      />
      <span className="text-[1.05rem] font-semibold tracking-tight text-cream">
        Syrus
      </span>
    </span>
  );
}
