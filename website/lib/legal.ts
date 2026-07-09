// Operator details for the Impressum + Privacy pages.
// ⚠️ Fill the REQUIRED fields before these pages are deployed publicly — an
// incomplete Impressum is itself non-compliant.
export const legal = {
  operator: {
    name: "Thomas Kadauke",
    street: "Essegger Str. 27",
    postalCode: "71067",
    city: "Sindelfingen",
    country: "Germany",
    email: "thomas.kadauke@gmail.com",
    phone: "", // none provided (email satisfies § 5 DDG; add later if desired)
    vatId: "", // none provided (add USt-IdNr. here if applicable)
  },
  effectiveDate: "2 July 2026",
};

// True once the legally-required Impressum fields are present.
export function impressumReady() {
  const o = legal.operator;
  return Boolean(o.name && o.street && o.postalCode && o.city && o.email);
}
