# Compliance assessments

A register of incidents and near-incidents that were assessed and found not to be a personal data breach, kept so the reasoning is on record (GDPR Art 5(2) accountability; Art 33(5) as a precaution). A confirmed breach follows [`breach-runbook.md`](breach-runbook.md) instead.

Threkir has no counsel or CISO. Each entry is decided by the owner, as controller, on a written research memo.

## 2026-10-22 — AI Coach context sent beyond the accepted disclosure

- **What happened**: the AI Coach sent Anthropic data that the AI disclosure the runner had accepted (v1-v5) did not name: recent gym-session summaries (from 2026-06-03); a 7-day nutrition summary, only with health-data consent (from 2026-06-03); and units, weekly goal, Coach personality, display name and resting / max HR (from 2026-05-03). Issue #1217, decisions § 2218.
- **Window**: from the Coach's prod go-live to the deploy that ships AI disclosure v6. The owner confirms the go-live date.
- **Who was affected**: runners on v1-v5 who had gym or food-log rows in the window and called `/api/coach`. Count with a prod query at deploy time and record it here.
- **Conclusion**: not a personal data breach. It was an intended disclosure to a contracted processor (Anthropic, under its Commercial Terms and DPA), with no loss of confidentiality, integrity or availability. The risk to runners is unlikely, so Art 33/34 is not triggered. It was a lawful-basis and transparency gap.
- **Remediation**: disclosure v6 names every field, and the per-field `COACH_CONTEXT_REGISTRY` refuses to send an unregistered one. Runners below v6 stop sending the new categories until they accept. The display name is no longer sent.
- **Decided by**: the owner, 2026-10-22, on `reviews/legal-ai-disclosure-v6.md`.
