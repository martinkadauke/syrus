import Image from "next/image";
import icon from "../public/syrus-icon.png";

export function Logo({ className = "" }: { className?: string }) {
  return (
    <span className={`inline-flex items-center gap-2.5 ${className}`}>
      <Image
        src={icon}
        alt=""
        width={28}
        height={28}
        priority
        className="rounded-[7px]"
      />
      <span className="text-[1.05rem] font-semibold tracking-tight text-cream">
        Syrus
      </span>
    </span>
  );
}
