import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'host-a-paid-yoga-class',
	source: '0781bf399db08c5b',
	title: 'Einen bezahlten Yoga- oder Pilateskurs anbieten',
	summary: 'Plane einen wiederkehrenden Kurs für deinen Club, begrenze die Matten, lege Drop-in-Preis und Rückerstattungsrichtlinie fest und hänge eine zeitgesteuerte Abfolge zum Mitmachen an.',
	sections: [
		{
			heading: 'Bevor du loslegst',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Bezahlte Kurse sind noch nicht live. Um Geld anzunehmen, muss dein eigenes Stripe-Konto verbunden sein ([[guide:get-paid-with-stripe|Für deine Events bezahlt werden]]) und das Bezahlsystem der Plattform eingeschaltet sein. Bis dahin bleibt der Schalter **Für dieses Event Geld verlangen** aus, und du kannst den Kurs weiterhin kostenlos anbieten.',
				},
				{
					type: 'list',
					items: [
						'Du musst Admin oder Eventorganisator des Clubs sein. Die Clubseite zeigt dir mit **Du bist Admin** oder **Du bist Eventorganisator**, was davon zutrifft.',
						'Preis, Kapazität, Wiederholungsplan und Session-Plan legst du alle im Web fest. Die Handy-App kann einen Kurs erstellen und zeigt ihn Mitgliedern an, hat aber keine Felder für Preis, Kapazität oder Session-Plan.',
						'Erstelle zuerst deine Abfolge, wenn du eine anhängen möchtest: siehe [[guide:build-a-session-plan|Einen Session-Plan erstellen]].',
					],
				},
			],
		},
		{
			heading: 'Kurs erstellen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne deinen Club, geh zum Tab **Events** und drücke **Neues Event**.',
						'Wähle unter **Veranstaltungstyp** die Option **Kurs**. Route, Distanz, Tempo und Rennergebnisse verschwinden, weil ein Kurs sie nicht braucht.',
						'Fülle **Disziplin** aus, zum Beispiel „Reformer-Pilates“. Damit wird der Stil in der Übersicht benannt.',
						'Lege optional die **Standard-Trainingsdauer** in Minuten fest. Ist eine Disziplin oder eine Dauer gesetzt, bekommen Teilnehmende auf der Kursseite einen Button **Als Training erfassen**.',
						'Wähle optional einen **Session-Plan**, um deine zeitgesteuerte Abfolge anzuhängen. Bleibt **Keiner** eingestellt, läuft der Kurs ohne.',
						'Gib ihm einen **Titel**, dann **Datum**, **Startzeit**, **Dauer** und einen **Treffpunkt**, den auch Ortsfremde finden, etwa die Adresse des Studios.',
					],
				},
			],
		},
		{
			heading: 'Zeitplan, Kapazität und Preis',
			blocks: [
				{
					type: 'steps',
					items: [
						'Wähle unter **Wiederholung** die Option **Wöchentlich**, **Alle 2 Wochen** oder **Monatlich**, dann die Tage und mit **Endet am** oder **Endet nach**, wann die Serie endet. Den Zeitplan kannst du nur beim Erstellen des Events wählen.',
						'Setze **Kapazität** auf die Zahl der Matten. Sind so viele Personen angemeldet, kommt die nächste stattdessen auf eine Warteliste.',
						'Schalte **Für dieses Event Geld verlangen** ein und gib **Preis** und **Währung** ein. Beide stehen fest, sobald das Event erstellt ist – prüfe sie also jetzt.',
						'Lege **Verkauf stoppen (Minuten vor Beginn)** fest. Null hält die Anmeldung bis direkt zum Beginn offen.',
						'Wähle eine **Rückerstattungsrichtlinie**: **Volle Rückerstattung bis zur Startzeit**, **Volle Rückerstattung bis 24 Std. vorher** oder **Keine Rückerstattung**. Siehe [[guide:refund-policies|Rückerstattungsrichtlinien]].',
						'Drücke **Event erstellen**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Bezahlte Anmeldung gibt es nur für Präsenzkurse. Jeder Termin eines wiederkehrenden Kurses wird einzeln bezahlt, wie ein Drop-in.',
				},
			],
		},
		{
			heading: 'Was deine Teilnehmenden sehen',
			blocks: [
				{
					type: 'list',
					items: [
						'Die Disziplin, Uhrzeit, den Ort, den **Preis** und einen Hinweis zur Stornierung, etwa **Kostenlose Stornierung bis 24 Stunden vor Beginn**.',
						'Einen Button mit der Aufschrift *Anmelden · 22,00 $* (mit deinem Preis), der zur Kasse führt. Wenn sie zurückkommen, steht dort **Zahlung bestätigt – du bist angemeldet.**',
						'**Ausverkauft**, wenn die Matten vergeben sind, mit **Auf die Warteliste**, solange der Verkauf läuft ([[guide:waitlist-and-claim-window|so funktioniert die Warteliste]]), und **Anmeldung geschlossen**, sobald der Verkauf endet.',
						'Deine Abfolge unter **Session-Abfolge**. Teilnehmende können sie öffnen und **Einheit starten** drücken, um zu Hause mitzumachen.',
					],
				},
				{
					type: 'p',
					text: 'Anmelden und Bezahlen geschieht im Web. Die Handy-App zeigt den Kurs, hat aber noch keinen Anmelde-Button.',
				},
			],
		},
		{
			heading: 'Am Kurstag und danach',
			blocks: [
				{
					type: 'list',
					items: [
						'Halte fest, wer gekommen ist: [[guide:take-attendance|Anwesenheit erfassen]].',
						'Musst du einen Termin absagen? [[guide:cancel-a-class|Einen Kurs absagen]] erstattet allen, die bezahlt haben.',
						'Das Geld geht abzüglich der Plattformgebühr auf dein eigenes Auszahlungskonto und erscheint unter **Einnahmen** in [[route:/settings/payouts|Auszahlungen]].',
					],
				},
				{
					type: 'p',
					text: 'Plan beim Erstellen vergessen? Auf der Kursseite können Organisatoren über **An ein Kurs-Event anhängen** in der Karte **Session-Abfolge** später einen auswählen.',
				},
			],
		},
	],
};
