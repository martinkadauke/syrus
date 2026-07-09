import type { Metadata } from "next";
import { LegalShell } from "../../components/legal-shell";
import { legal } from "../../lib/legal";

export const metadata: Metadata = {
  title: "Impressum",
  description:
    "Legal notice and operator information for syrus-ai.dev pursuant to § 5 DDG.",
  alternates: { canonical: "/impressum" },
};

export default function Impressum() {
  const o = legal.operator;
  return (
    <LegalShell title="Impressum">
      <p>Information pursuant to § 5 DDG (Digitale-Dienste-Gesetz).</p>

      <h2>Operator</h2>
      <p>
        {o.name}
        {o.street ? (
          <>
            <br />
            {o.street}
          </>
        ) : null}
        <br />
        {o.postalCode} {o.city}
        <br />
        {o.country}
      </p>

      <h2>Contact</h2>
      <p>
        Email: <a href={`mailto:${o.email}`}>{o.email}</a>
        {o.phone ? (
          <>
            <br />
            Phone: {o.phone}
          </>
        ) : null}
      </p>

      {o.vatId ? (
        <>
          <h2>VAT identification number</h2>
          <p>VAT ID pursuant to § 27a UStG: {o.vatId}</p>
        </>
      ) : null}

      <h2>Responsible for content pursuant to § 18 (2) MStV</h2>
      <p>
        {o.name}
        {o.street ? `, ${o.street}, ${o.postalCode} ${o.city}` : ""}
      </p>

      <h2>Consumer dispute resolution</h2>
      <p>
        We are neither willing nor obliged to participate in dispute-resolution
        proceedings before a consumer arbitration board (§ 36 VSBG).
      </p>

      <h2>Liability for content</h2>
      <p>
        As a service provider, we are responsible for our own content on these
        pages in accordance with general law (§ 7 (1) DDG). We are not obliged to
        monitor transmitted or stored third-party information (§§ 8–10 DDG).
        Obligations to remove or block the use of information under general law
        remain unaffected; liability in this respect is only possible from the
        point at which we become aware of a specific infringement. We will remove
        such content promptly upon becoming aware of it.
      </p>

      <h2>Liability for links</h2>
      <p>
        Our site may contain links to external websites over whose content we
        have no control. We therefore cannot accept any liability for such
        third-party content. The respective provider or operator of the linked
        pages is always responsible for their content. We will remove such links
        promptly if we become aware of any legal infringements.
      </p>

      <h2>Copyright</h2>
      <p>
        The content and works on these pages are subject to German copyright law.
        Reproduction, editing, distribution and any kind of use beyond the limits
        of copyright require the written consent of the respective author or
        creator.
      </p>
    </LegalShell>
  );
}
