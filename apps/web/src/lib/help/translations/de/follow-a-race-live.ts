import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'follow-a-race-live',
	title: 'Ein Rennen live verfolgen',
	summary: 'Verfolge ein Rennen in Echtzeit auf der Live-Rennseite: Teilnehmende auf einer Karte, wer auf der Strecke ist und wer auf jeder Strecke im Ziel ist.',
	sections: [
		{
			heading: 'Die Live-Seite öffnen',
			blocks: [
				{
					type: 'p',
					text: 'Der Veranstalter teilt einen Link zur Live-Rennseite, oder du öffnest das Event, falls du es sehen kannst, und wählst **Zuschaueransicht**. Du brauchst kein Konto. Ist das Event **Nur für Mitglieder**, musst du Mitglied des Clubs sein, um es zu sehen.',
				},
				{
					type: 'p',
					text: 'Oben auf der Seite steht der Status des Rennens:',
				},
				{
					type: 'list',
					items: [
						'**Vor dem Rennen**: Der Veranstalter hat die Rennuhr noch nicht scharfgestellt.',
						'**Bereit**: Die Uhr ist scharfgestellt und wartet auf den Start.',
						'**Läuft**: Das Rennen ist im Gange, mit der verstrichenen Zeit.',
						'**Beendet**: Das Rennen ist vorbei.',
						'**Abgesagt**: Der Veranstalter hat das Rennen abgesagt.',
					],
				},
			],
		},
		{
			heading: 'Die Karte',
			blocks: [
				{
					type: 'p',
					text: 'Sofern du Karten nicht schon in deinen Cookie-Einstellungen erlaubt hast, bleibt die Karte aus, bis du **Karte laden** wählst, denn beim Laden wird deine IP-Adresse an unseren Anbieter für Kartenkacheln gesendet. Nach dem Laden ist jede teilnehmende Person ein farbiger Punkt mit einer kurzen Spur ihres jüngsten Wegs. Die Handys und Uhren der Teilnehmenden senden etwa alle 10 Sekunden eine Position, und die Seite aktualisiert sich von selbst.',
				},
			],
		},
		{
			heading: 'Unterwegs auf der Strecke',
			blocks: [
				{
					type: 'p',
					text: 'Die Liste **Auf der Strecke** zeigt alle Teilnehmenden, die eine Position gesendet haben, die am weitesten Gekommenen zuerst, mit Distanz, Tempo und verstrichener Zeit; hat das Rennen mehr als eine Strecke, gibt es eine Liste pro Strecke. Jede Zeile zeigt außerdem, wie lange die letzte Aktualisierung her ist.',
				},
				{
					type: 'p',
					text: 'Es gibt keine eigene Kennzeichnung für „pausiert“. Wer stehen geblieben ist (um einen Schnürsenkel zu binden, an einer Verpflegungsstelle oder weil die Aufzeichnung pausiert wurde) oder kein Signal mehr hat, wird einfach nicht mehr aktualisiert. Nach etwa 90 Sekunden ohne Aktualisierung wird die Zeile als **VERZÖGERT** markiert. Das heißt nicht, dass etwas nicht stimmt; oft fehlt einfach nur das Signal.',
				},
			],
		},
		{
			heading: 'Im Ziel',
			blocks: [
				{
					type: 'p',
					text: 'Wer im Ziel ist, erscheint unter **Beendet**, sobald das Ergebnis eintrifft, mit einer Liste pro Strecke, wenn das Rennen mehr als eine hat. Wer nicht ins Ziel gekommen ist, steht unter **Nicht beendet**. Ein Ergebnis, das der Veranstalter noch nicht genehmigt hat, ist als **Ausstehend** markiert.',
				},
				{
					type: 'p',
					text: 'Was die Zeiten und Abzeichen bedeuten, erklärt [[guide:race-results-explained|Rennergebnisse erklärt]].',
				},
			],
		},
		{
			heading: 'Datenschutz',
			blocks: [
				{
					type: 'list',
					items: [
						'Die echten Namen der Teilnehmenden sehen nur Personen, die über ein Folgen mit ihnen verbunden sind, egal in welche Richtung. Alle anderen sehen ein anonymes Kürzel wie Läufer #A1B2.',
						'In der Nähe der Datenschutzzone einer teilnehmenden Person wird ihre genaue Position verborgen. Du siehst stattdessen **Zuletzt hier in der Nähe gesehen · ungefähr**, dargestellt als hohler Ring statt als Punkt.',
						'Teilnehmende, die der Veranstalter aus einer Startnummernliste importiert hat, haben kein Konto und behalten daher den Namen, den der Veranstalter eingegeben hat.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Alle mit dem Link können zuschauen. Wenn du selbst mitläufst und lieber nicht live verfolgt werden möchtest, sprich vor dem Rennen mit dem Veranstalter.',
				},
			],
		},
	],
	sources: {
		title: '2c62c5274378a304',
		summary: '6907f1876e7b883e',
		's0.heading': '9e53c8e8fdd29829',
		's0.b0': '386a683bed4bd1dd',
		's0.b1': 'c2d62153581d81fa',
		's0.b2.i0': '3a6d56e541fe4565',
		's0.b2.i1': 'c3dd12cae69c5cf5',
		's0.b2.i2': '120d1d8d969ced75',
		's0.b2.i3': 'fbe2e397efb8ef5e',
		's0.b2.i4': '1709d9ad712d85d2',
		's1.heading': 'dc711bb38f5066a7',
		's1.b0': 'f40d0503826f0955',
		's2.heading': '46db515d7f1689a7',
		's2.b0': '3316e288511685d1',
		's2.b1': 'cff7f7798a6785c9',
		's3.heading': '7804f7a79a9eee32',
		's3.b0': '4355700d3a60d89c',
		's3.b1': 'ea613ba62f6ba84a',
		's4.heading': '54a57c3147c49f33',
		's4.b0.i0': 'b8c1ad08a0dc3387',
		's4.b0.i1': '7cf40c647db03cc3',
		's4.b0.i2': 'edbbe7f08d1cf63e',
		's4.b1': '1bb7132a7305e850',
	},
};
