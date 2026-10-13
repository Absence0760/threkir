import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'refund-policies',
	title: 'Rückerstattungsrichtlinien und das Stornieren deiner Anmeldung',
	summary: 'Wie die drei Rückerstattungsrichtlinien funktionieren, wie Teilnehmende eine bezahlte Anmeldung stornieren und was sie dabei sehen.',
	sections: [
		{
			heading: 'Bevor du loslegst',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Bezahlte Anmeldung ist noch nicht live. Dafür muss das Stripe-Konto des Veranstalters verbunden und das Bezahlsystem der Plattform eingeschaltet sein. Bis dahin kann für kein Event Geld verlangt werden, es gibt also nichts zu erstatten.',
				},
			],
		},
		{
			heading: 'Die drei Richtlinien',
			blocks: [
				{
					type: 'p',
					text: 'Der Veranstalter wählt beim Erstellen eines bezahlten Events eine **Rückerstattungsrichtlinie**. Sie bestimmt, was jemand zurückbekommt, wenn *er selbst* storniert, und sie wird auf der Eventseite angezeigt, bevor jemand bezahlt.',
				},
				{
					type: 'list',
					items: [
						'**Volle Rückerstattung bis zur Startzeit**: Teilnehmende sehen **Kostenlose Stornierung bis zum Beginn der Veranstaltung**.',
						'**Volle Rückerstattung bis 24 Std. vorher**: angezeigt als **Kostenlose Stornierung bis 24 Stunden vor Beginn**. Das ist die Voreinstellung.',
						'**Keine Rückerstattung**: angezeigt als **Keine Erstattung bei Stornierung**.',
					],
				},
				{
					type: 'p',
					text: 'Eine Erstattung gilt ganz oder gar nicht: Innerhalb der Frist bekommst du den vollen Preis zurück, außerhalb bekommst du nichts zurück. Die Frist wird ab dem Beginn des Termins gerechnet, für den du dich angemeldet hast.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Die Richtlinie gilt nur, wenn Teilnehmende stornieren. Sagt der Veranstalter einen Kurs ab, bekommen alle, die bezahlt haben, unabhängig von der Richtlinie den vollen Betrag erstattet: siehe [[guide:cancel-a-class|Einen Kurs absagen]].',
				},
			],
		},
		{
			heading: 'Deine eigene Anmeldung stornieren',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne das Event im Web. Wo **Du bist angemeldet** steht, drücke **Anmeldung stornieren**.',
						'Lies den Dialog. Innerhalb der Erstattungsfrist steht dort, dass du das Geld auf dein ursprüngliches Zahlungsmittel zurückbekommst und dein Platz für jemanden auf der Warteliste frei wird.',
						'Drücke **Anmeldung stornieren**, um fortzufahren, oder **Platz behalten**, um abzubrechen.',
					],
				},
				{
					type: 'p',
					text: 'Danach siehst du **Erstattung gestartet – es kann einige Tage dauern, bis sie erscheint. Dein Platz wurde freigegeben.** Bis deine Bank sie bestätigt, zeigt die Seite **Erstattung läuft**.',
				},
				{
					type: 'p',
					text: 'Hast du die Kasse vor dem Bezahlen verlassen, storniert derselbe Button stattdessen die ausstehende Anmeldung: Dein reservierter Platz wird freigegeben und es wird keine Zahlung eingezogen.',
				},
			],
		},
		{
			heading: 'Außerhalb der Erstattungsfrist',
			blocks: [
				{
					type: 'p',
					text: 'Nach Ablauf der Frist oder bei einem Event mit **Keine Rückerstattung** kann die App deine Anmeldung nicht für dich stornieren. Der Dialog warnt dich vorher, du behältst deinen Platz, und wenn du trotzdem fortfährst, siehst du **Diese Anmeldung liegt außerhalb der Erstattungsfrist. Wende dich zum Stornieren an den Veranstalter.**',
				},
			],
		},
		{
			heading: 'Wenn eine Erstattung nicht ankommt',
			blocks: [
				{
					type: 'p',
					text: 'Gelegentlich schickt eine Bank eine Erstattung zurück. Die Eventseite zeigt dann **Deine Erstattung ist nicht angekommen**, und eine Benachrichtigung meldet **Eine Erstattung ist nicht durchgegangen – wir melden uns**. Du musst nicht erneut bezahlen; nutze **Abrechnung kontaktieren**, und du bekommst das Geld auf anderem Weg zurück.',
				},
			],
		},
	],
	sources: {
		title: 'c4fa256f459076d1',
		summary: '9baf65491beccb1b',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '30a11867ccf5b3d2',
		's1.heading': '9b547a04e62b40db',
		's1.b0': 'ac02c018440619c7',
		's1.b1.i0': '78212cc5dd0fc966',
		's1.b1.i1': '109e0ad8958dff1d',
		's1.b1.i2': 'c0df4938a31c7529',
		's1.b2': 'f6431402b8fb3d47',
		's1.b3': '2ba18e4b6ad11943',
		's2.heading': '75a59fd46f7b58e9',
		's2.b0.i0': '6acdfa50019e0f37',
		's2.b0.i1': '46cf562b1c2b6db6',
		's2.b0.i2': '769ffd95161fd1d5',
		's2.b1': '36a76c72aba97bcd',
		's2.b2': '3cd5377cc8a2bfcf',
		's3.heading': '41bf02bef2f3e906',
		's3.b0': '79864fedf6e2a3a4',
		's4.heading': '9bc91646456ca461',
		's4.b0': '99e677611ddc18a9',
	},
};
