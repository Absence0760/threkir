import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'waitlist-and-claim-window',
	title: 'Wartelisten und die 12-Stunden-Frist',
	summary: 'Wie das Beitreten zu einem vollen Kurs funktioniert, wie ein frei gewordener Platz bei einem bezahlten Kurs 12 Stunden für dich reserviert wird und was passiert, wenn du ihn nicht sicherst.',
	sections: [
		{
			heading: 'Kostenlose Kurse: Du rückst automatisch nach',
			blocks: [
				{
					type: 'p',
					text: 'Ist ein kostenloser Kurs mit **Kapazität** voll, setzt dich **Ich bin dabei** auf die Warteliste, und deine Antwort zeigt **Warteliste**. Sagt jemand ab, rückt die Person, die am längsten auf der Warteliste steht, automatisch auf **Zugesagt** nach; du musst nichts sichern. Das funktioniert im Web und in der Handy-App.',
				},
			],
		},
		{
			heading: 'Bezahlte Kurse: Ein Platz wird reserviert, dann bezahlst du',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Bezahlte Kurse sind noch nicht live: Dafür muss das Stripe-Konto des Veranstalters verbunden und das Bezahlsystem der Plattform eingeschaltet sein. Alles in diesem Abschnitt gilt, sobald das der Fall ist.',
				},
				{
					type: 'p',
					text: 'Niemand wird belastet, nur weil er auf einer Warteliste steht. Stattdessen wird dir ein frei gewordener Platz angeboten, und du bezahlst, um ihn zu übernehmen.',
				},
				{
					type: 'steps',
					items: [
						'Bei einem vollen bezahlten Kurs zeigt die Seite **Ausverkauft**. Solange der Verkauf noch läuft, drücke **Auf die Warteliste**. Du siehst **Du stehst auf der Warteliste. Wird ein Platz frei, reservieren wir ihn für dich und sagen dir Bescheid.**',
						'Wird ein Platz frei und du bist als Nächstes dran, bekommst du eine Benachrichtigung: *Bei „Tuesday Reformer“ ist ein Platz frei geworden und für dich reserviert – bezahle, um ihn zu sichern*.',
						'Öffne den Kurs im Web. Dort steht, wann deine Reservierung endet, zum Beispiel *Ein Platz ist bis Di., 6. Mai, 18:00 für dich reserviert. Bezahle, um ihn zu sichern – sonst geht er an die nächste Person auf der Warteliste.*',
						'Drücke den Button zum Sichern (er lautet *Platz sichern* mit dem Preis) und bezahle an der Kasse. Nach der Zahlung bist du wie alle anderen angemeldet.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Das Sichern geschieht im Web. Die Handy-App zeigt die Benachrichtigung und öffnet den Kurs, hat aber noch keine Kasse – öffne den Kurs also zum Bezahlen in einem Browser.',
				},
			],
		},
		{
			heading: 'Wie lange die Reservierung gilt',
			blocks: [
				{
					type: 'list',
					items: [
						'Du hast 12 Stunden Zeit, den Platz zu sichern – lang genug, dass niemand einen Platz verliert, nur weil er schläft.',
						'Die Reservierung endet früher, wenn der Verkauf für diesen Kurs schließt (die vom Veranstalter festgelegte Verkaufsschluss-Zeit vor Beginn). Nach Verkaufsschluss wird kein Platz mehr angeboten, weil ihn niemand mehr bezahlen könnte.',
						'Solange dein Platz reserviert ist, kann ihn niemand sonst kaufen, auch wenn der Kurs für andere voll aussieht.',
						'Bist du gerade mitten im Bezahlvorgang, wenn die Zeit abläuft, bleibt die Reservierung bestehen, solange dieser Bezahlvorgang noch offen ist.',
					],
				},
			],
		},
		{
			heading: 'Wenn du den Platz nicht sicherst',
			blocks: [
				{
					type: 'p',
					text: 'Läuft die Reservierung ab, wird der Platz der nächsten Person auf der Warteliste angeboten, und du verlässt die Warteliste. Willst du trotzdem noch teilnehmen, drücke erneut **Auf die Warteliste**; du kommst dann ans Ende der Schlange.',
				},
				{
					type: 'p',
					text: 'Während des Wartens anders entschieden? Drücke **Warteliste verlassen**. Du wirst gewarnt, dass du deinen Platz in der Schlange verlierst; trittst du später wieder bei, kommst du ans Ende. Wird bereits ein Platz für dich reserviert und du willst ihn nicht, lass die Reservierung einfach ablaufen.',
				},
			],
		},
		{
			heading: 'Für Veranstalter',
			blocks: [
				{
					type: 'list',
					items: [
						'Die Warteliste läuft von selbst. Lege für den Kurs eine **Kapazität** fest, der Rest geschieht automatisch; die 12-Stunden-Frist lässt sich nicht pro Kurs ändern.',
						'Ein reservierter Platz zählt zu deiner Kapazität, sodass du nie mehr Leute als Matten hast.',
						'Storniert jemand mit Erstattung, geht sein Platz an die Warteliste. Sagst du einen Termin ab, rückt niemand von der Warteliste nach: siehe [[guide:cancel-a-class|Einen Kurs absagen]].',
					],
				},
			],
		},
	],
	sources: {
		title: 'ff29dd616c432abb',
		summary: 'afd5b04d5200ae72',
		's0.heading': '1a4ad94ad3a45f95',
		's0.b0': 'cc59a78b4fa99e3d',
		's1.heading': '45a160f0c13ecbad',
		's1.b0': '360073628758585f',
		's1.b1': '572cda34a27eb2a9',
		's1.b2.i0': '5ee5608e87186c87',
		's1.b2.i1': '8e62e44aa4cb3c4c',
		's1.b2.i2': '2411acbf338bf29b',
		's1.b2.i3': '3fc20f1431c75da8',
		's1.b3': 'ac88ce64fbfe661e',
		's2.heading': '3120ebc77dff029c',
		's2.b0.i0': 'ac867875f2d6559e',
		's2.b0.i1': '10c7227bdd74a7f7',
		's2.b0.i2': 'ec3aaee401a8d661',
		's2.b0.i3': '115c393a06a875a2',
		's3.heading': '1c4542c4b4456638',
		's3.b0': '5f2b4c5d07b65be4',
		's3.b1': '080220c843290021',
		's4.heading': '3475448cc5eb2d77',
		's4.b0.i0': '9fc9b8683d8e30fd',
		's4.b0.i1': 'f602296c6993b85f',
		's4.b0.i2': '4d6cf70ea800fae3',
	},
};
