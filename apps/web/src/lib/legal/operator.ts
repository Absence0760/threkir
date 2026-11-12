export interface LegalRepresentative {
	name: string;
	address: string;
	email: string;
}

/**
 * The operator has decided not to provide this fact. Distinct from `null`,
 * which means the fact is still pending: a pending fact raises the pages'
 * "being finalised" banner, a declined one renders as a plain statement
 * that it is not provided.
 */
export const NOT_PROVIDED = 'not-provided';
export type NotProvided = typeof NOT_PROVIDED;

export interface OperatorFacts {
	serviceName: string;
	controllerDescription: string;
	postalAddress: string | NotProvided | null;
	governingLaw: string | null;
	euRepresentative: LegalRepresentative | NotProvided | null;
	ukRepresentative: LegalRepresentative | NotProvided | null;
}

// The legal pages (/privacy, /terms, /cookie-notice) are complete legal
// text; these are the operator facts they render. A null renders a
// clearly-marked "pending" line instead of a fabricated fact (the
// fail-closed gate per decisions §150); NOT_PROVIDED records a decision not
// to provide the fact. The owner decided on 2026-10-06 (issue #1061, M6)
// to publish no postal address and appoint no Art 27 representatives for
// now, so those three render as not provided rather than pending —
// docs/compliance/eu-representative.md tracks the representatives as a
// later option. Changing any of these still needs counsel sign-off before
// a public launch.
export const OPERATOR: OperatorFacts = {
	serviceName: 'Threkir',
	controllerDescription: 'Jared Howard, an individual operating as a sole proprietor',
	postalAddress: NOT_PROVIDED,
	governingLaw: 'the Commonwealth of Virginia, United States',
	euRepresentative: NOT_PROVIDED,
	ukRepresentative: NOT_PROVIDED,
};

/** True when no operator fact is still pending (null). */
export function operatorFactsComplete(facts: OperatorFacts): boolean {
	return (
		facts.postalAddress !== null &&
		facts.governingLaw !== null &&
		facts.euRepresentative !== null &&
		facts.ukRepresentative !== null
	);
}

export const OPERATOR_FACTS_COMPLETE = operatorFactsComplete(OPERATOR);
