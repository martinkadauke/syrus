export function Logo({ className = "" }: { className?: string }) {
  return (
    <span className={`inline-flex items-center gap-2.5 ${className}`}>
      <img
        src="/syrus-icon.png"
        alt=""
        width={28}
        height={28}
        className="rounded-[7px]"
      />
      <span className="text-[1.05rem] font-semibold tracking-tight text-cream">
        Syrus
      </span>
    </span>
  );
}
