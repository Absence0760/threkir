import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'refund-policies',
	source: 'be8b580dfc980abf',
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
};
