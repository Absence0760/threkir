import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'get-paid-with-stripe',
	source: 'd4950e6117ea250a',
	title: 'Für deine Events bezahlt werden',
	summary: 'Verbinde einmalig ein Stripe-Auszahlungskonto, damit deine Kurse und Events Zahlungen annehmen können – das Geld geht an dich, nicht an den Club.',
	sections: [
		{
			heading: 'Bevor du loslegst',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Bezahlte Anmeldung ist noch nicht live. Um für ein Event Geld zu verlangen, braucht es zwei Dinge: dein eigenes, hier verbundenes Stripe-Konto und die Plattform, die ihr Bezahlsystem einschaltet. Solange nicht beides zutrifft, kann niemand belastet werden. Erscheint nach dem Drücken von **Zahlungen einrichten** die Meldung **Zahlungen sind in diesem Build noch nicht konfiguriert.**, fehlt noch das Zweite, und du musst vorerst nichts tun.',
				},
				{
					type: 'p',
					text: 'Auszahlungen gehören *dir*, nicht einem Club. Das Geld für ein Event geht an die Person, die es veranstaltet. So sieht ein Mitorganisator, der nie einen Kurs leitet, nie Geld, das nicht ihm gehört, und du behältst deine Einnahmen, wenn du nicht mehr für einen Club organisierst. Ein Auszahlungskonto gilt für jeden Club, für den du veranstaltest, und für jede Art von Event, auch ein [[guide:set-up-a-race|Rennen]].',
				},
			],
		},
		{
			heading: 'Auszahlungskonto verbinden',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne im Web [[route:/settings/payouts|Einstellungen, Auszahlungen]].',
						'Drücke **Zahlungen einrichten**. Du wirst zu Stripe weitergeleitet, um deine Angaben und das Bankkonto einzugeben, auf das du ausgezahlt werden willst.',
						'Schließ die Schritte bei Stripe ab. Wenn du zurückkommst, zeigt die Seite deinen Status.',
						'Steht dort **Einrichtung unvollständig – abschließen, um Zahlungen zu starten** oder **Dein Auszahlungskonto benötigt Aufmerksamkeit, bevor du Zahlungen annehmen kannst**, drücke **Zahlungseinrichtung abschließen**, um zu Stripe zurückzukehren und dort weiterzumachen, wo du aufgehört hast.',
					],
				},
			],
		},
		{
			heading: 'Was der Status bedeutet',
			blocks: [
				{
					type: 'list',
					items: [
						'**Bereit für Zahlungen**: Stripe hat Zahlungen auf deinem Konto freigeschaltet, und **Stripe-Dashboard öffnen** bringt dich zu deinem Stripe-Konto. Das ist mit „charges enabled“ gemeint, und nur in diesem Zustand lässt sich der Schalter **Für dieses Event Geld verlangen** bei einem neuen Event einschalten.',
						'**Einrichtung unvollständig – abschließen, um Zahlungen zu starten**: Stripe braucht noch etwas von dir, bevor es eine Zahlung annimmt.',
						'**Dein Auszahlungskonto benötigt Aufmerksamkeit, bevor du Zahlungen annehmen kannst**: Stripe hat das Konto eingeschränkt, meist weil es weitere Informationen möchte. **Zahlungseinrichtung abschließen** führt dich zu dem, was verlangt wird.',
					],
				},
				{
					type: 'p',
					text: 'Solange du keine Zahlungen annehmen kannst, zeigt das Event-Formular **Richte Auszahlungen ein, um für Events Geld zu verlangen.** mit einem Link **Auszahlungen einrichten** zurück zu dieser Seite.',
				},
			],
		},
		{
			heading: 'Gebühren und Zuständigkeiten',
			blocks: [
				{
					type: 'p',
					text: 'Die Plattform behält von jeder Anmeldung eine kleine Gebühr ein, die in deinen Einnahmen als **Plattformgebühr** erscheint. Die Plattform ist der Händler (Merchant of Record): Die Zahlung trägt ihren Namen auf der Abrechnung deiner Käufer, Erstattungen stellt die Plattform gemäß der Rückerstattungsrichtlinie aus, die du für jedes Event festlegst, und eine angefochtene Zahlung wird vom Stripe-Konto der Plattform abgebucht, nicht von deinem. Wird eine Bestellung vollständig erstattet, wird auch die Plattformgebühr darauf zurückgegeben.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Erstatte Käufern nicht von Hand in Stripe. Nutze die Wege der App ([[guide:refund-policies|eine Stornierung durch Käufer]] oder [[guide:cancel-a-class|das Absagen eines Termins]]), die deine Auszahlung und die Plattformgebühr gemeinsam zurückbuchen und deine Einnahmenzahlen stimmig halten.',
				},
			],
		},
		{
			heading: 'Deine Einnahmen ansehen',
			blocks: [
				{
					type: 'p',
					text: 'Der Bereich **Einnahmen** auf derselben Seite zeigt, was du für deine Kurse bekommen hast, ein Block pro Monat und Währung. Ein Kurs wird dem Monat zugeordnet, in dem er in seiner eigenen Zeitzone stattfand, nicht dem Monat der Zahlung – „meine Oktober-Kurse“ sind also die Kurse, die im Oktober stattgefunden haben.',
				},
				{
					type: 'list',
					items: [
						'**Anmeldungen**, **Brutto**, **Erstattet** und **Plattformgebühr** für den Monat und am Ende **Netto für dich**.',
						'Eine Aufschlüsselung nach Kurs mit den Spalten **Kurs** und **Wann**.',
						'Eine Erstattung, die die Bank zurückgeschickt hat, bleibt bis zur Klärung außerhalb der Summen, und der Bereich zeigt, wie viele es davon gibt.',
					],
				},
				{
					type: 'p',
					text: 'Bevor jemand bezahlt hat, steht dort **Noch keine bezahlten Anmeldungen. Sobald jemand für einen deiner Kurse bezahlt, erscheint er hier.** Einnahmen gibt es vorerst nur im Web.',
				},
			],
		},
	],
};
