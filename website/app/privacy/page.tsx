import type { Metadata } from "next";
import { LegalShell } from "../../components/legal-shell";
import { legal } from "../../lib/legal";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "How syrus-ai.dev handles personal data: server logs, the demo form, and your GDPR rights. No analytics, no tracking.",
  alternates: { canonical: "/privacy" },
};

export default function Privacy() {
  const o = legal.operator;
  const address = [o.street, `${o.postalCode} ${o.city}`.trim(), o.country]
    .filter(Boolean)
    .join(", ");

  return (
    <LegalShell title="Privacy Policy" updated={legal.effectiveDate}>
      <p>
        This policy explains what personal data we process when you use
        syrus-ai.dev, why, and the rights you have. We keep data collection to a
        minimum: the site uses no analytics, no advertising, and no third-party
        tracking.
      </p>

      <h2>1. Controller</h2>
      <p>
        {o.name}
        {address ? `, ${address}` : ""}. Email:{" "}
        <a href={`mailto:${o.email}`}>{o.email}</a>
        {o.phone ? `. Phone: ${o.phone}` : ""}. See our{" "}
        <a href="/impressum">Impressum</a> for full details.
      </p>

      <h2>2. Server log data</h2>
      <p>
        When you access the site, our server and reverse proxy automatically
        process technical data needed to deliver the pages and keep the service
        secure and stable: your IP address, the date and time of the request, the
        page or file requested, the referring URL, and your
        browser/operating-system information.
      </p>
      <p>
        <strong>Purpose &amp; legal basis:</strong> operation, security and
        stability of the site, based on our legitimate interest (Art. 6(1)(f)
        GDPR). This data is stored only briefly and then deleted or anonymised; it
        is not combined with other data or used to identify you personally.
      </p>

      <h2>3. Downloads</h2>
      <p>
        The macOS app is served directly from our own server. Downloading it
        processes the same server log data described above; no additional personal
        data is collected.
      </p>

      <h2>4. Demo request form</h2>
      <p>
        If you submit the “Request a demo” form, we process the details you
        provide — your name, email address, company (optional) and message — in
        order to respond to your enquiry and send you a confirmation email.
      </p>
      <p>
        <strong>Legal basis:</strong> steps taken at your request prior to
        entering into a contract, and our legitimate interest in responding to
        enquiries (Art. 6(1)(b) and (f) GDPR).
      </p>
      <p>
        <strong>Recipients:</strong> the submitted data is delivered to us by
        email through our email provider, <strong>Strato AG</strong> (Germany),
        acting as a processor on our behalf (Art. 28 GDPR). We do not share it
        with any other third parties.
      </p>
      <p>
        <strong>Retention:</strong> we keep the data for as long as needed to
        handle your request and any follow-up correspondence, then delete it
        unless statutory retention periods apply.
      </p>

      <h2>5. Local storage in your browser</h2>
      <p>
        We store two small values in your browser’s local storage: your
        colour-theme preference and the fact that you dismissed the cookie notice.
        These stay on your device, are not transmitted to us, and are not used for
        tracking or profiling. Because they are strictly functional, no consent is
        required. You can clear them at any time via your browser settings.
      </p>

      <h2>6. Cookies, analytics &amp; third parties</h2>
      <p>
        We use no tracking or advertising cookies, no web-analytics tools, and no
        third-party embeds or content-delivery networks. Web fonts are
        self-hosted, so no data is sent to Google or other font providers when you
        load the site.
      </p>

      <h2>7. Data security</h2>
      <p>The site is served exclusively over an encrypted HTTPS/TLS connection.</p>

      <h2>8. Your rights</h2>
      <p>
        Under the GDPR you have the right to access your data (Art. 15), to
        rectification (Art. 16), to erasure (Art. 17), to restriction of
        processing (Art. 18), to data portability (Art. 20), and to object to
        processing based on our legitimate interests (Art. 21). Where processing
        is based on consent, you may withdraw it at any time with effect for the
        future.
      </p>
      <p>
        To exercise any of these rights, contact us at{" "}
        <a href={`mailto:${o.email}`}>{o.email}</a>.
      </p>
      <p>
        You also have the right to lodge a complaint with a data-protection
        supervisory authority (Art. 77 GDPR), for example the authority
        responsible for your place of residence in Germany.
      </p>

      <h2>9. Changes to this policy</h2>
      <p>
        We may update this policy to reflect changes to the site or legal
        requirements. The current version always applies; see the “last updated”
        date above.
      </p>
    </LegalShell>
  );
}
