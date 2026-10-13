import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'get-paid-with-stripe',
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
	sources: {
		title: 'f9207157d1280332',
		summary: '790080559509072a',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '94bdd45ffa45992b',
		's0.b1': 'a2c35333af5a1b69',
		's1.heading': '3f872765a64cbf87',
		's1.b0.i0': 'e50bbd6128265cce',
		's1.b0.i1': '0f46885c40eac7c9',
		's1.b0.i2': '5c865b5f5c133459',
		's1.b0.i3': '8dda9f151d4fc524',
		's2.heading': '1efee8cc7e563d7a',
		's2.b0.i0': '02332a68186a1ac7',
		's2.b0.i1': '7215a841b76d02d7',
		's2.b0.i2': '482a0774b06a0a05',
		's2.b1': '97218ad8cd1cbafc',
		's3.heading': 'dd310d8f72e99c50',
		's3.b0': '67194d07a6c76aca',
		's3.b1': 'b0ca08b2dbcff463',
		's4.heading': 'e819e6fcb745f74c',
		's4.b0': '158c0402a17ba033',
		's4.b1.i0': '1f9a53c012335688',
		's4.b1.i1': '69d92aabe5b8e3c6',
		's4.b1.i2': 'da7f4f45de54e110',
		's4.b2': 'e6e13ff04eb65dc4',
	},
};
