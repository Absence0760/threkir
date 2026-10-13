import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'host-a-paid-gym-class',
	source: '3b7a87855005ee69',
	title: 'Einen bezahlten HIIT-, Kraft- oder Bootcamp-Kurs anbieten',
	summary: 'Plane einen wiederkehrenden Gym-Kurs mit Platzlimit und Drop-in-Preis, teile das Training als Club-Routine und lass Teilnehmende es in ihrem eigenen Verlauf erfassen.',
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
					type: 'p',
					text: 'Du musst Admin oder Eventorganisator des Clubs sein. Preis, Kapazität und Wiederholungsplan legst du im Web fest; die Handy-App kann einen Kurs erstellen, hat dafür aber keine Felder.',
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
						'Wähle unter **Veranstaltungstyp** die Option **Kurs**. Route, Distanz, Tempo und Rennergebnisse werden bei einem Kurs ausgeblendet.',
						'Fülle **Disziplin** aus, zum Beispiel „HIIT“ oder „Bootcamp“, und einen **Titel**, den die Leute im Kalender wiedererkennen.',
						'Setze **Standard-Trainingsdauer** auf die Kurslänge in Minuten. Damit können Teilnehmende den Kurs danach mit einem Tippen erfassen.',
						'Lege **Datum**, **Startzeit**, **Dauer** und **Treffpunkt** fest.',
						'Wähle unter **Wiederholung** die Option **Wöchentlich**, **Alle 2 Wochen** oder **Monatlich** und die Tage. Das geht nur beim Erstellen des Events.',
						'Setze **Kapazität** auf die Zahl deiner Racks, Bikes oder Plätze.',
						'Schalte **Für dieses Event Geld verlangen** ein und lege dann **Preis**, **Währung**, **Verkauf stoppen (Minuten vor Beginn)** und eine **Rückerstattungsrichtlinie** fest. Preis und Währung lassen sich nach dem Erstellen des Events nicht mehr ändern.',
						'Drücke **Event erstellen**.',
					],
				},
			],
		},
		{
			heading: 'Das Training mit deinem Kurs teilen',
			blocks: [
				{
					type: 'p',
					text: 'Ein Kurs kann noch keine Gym-Routine direkt mitführen. Veröffentliche deine Routine stattdessen im Club, wo Mitglieder sie in ihre eigenen Routinen kopieren und absolvieren können.',
				},
				{
					type: 'steps',
					items: [
						'Erstelle die Routine: siehe [[guide:build-a-gym-routine|Eine Gym-Routine erstellen]].',
						'Öffne die Routine, wähle unter **In einem Club veröffentlichen** deinen Club bei **Club auswählen…** und drücke **Veröffentlichen**.',
						'Sie erscheint im Tab **Vorlagen** des Clubs unter **Gym-Routine-Vorlagen**, markiert als **Club-Vorlage**. Mitglieder drücken **Übernehmen**, um ihre eigene Kopie zu bekommen.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Club-Admins können auch direkt zum Tab **Vorlagen** gehen, **Vorlage hinzufügen** drücken und **Gym-Routine** wählen. Sie wird in einem Schritt als Club-Vorlage gespeichert.',
				},
			],
		},
		{
			heading: 'Teilnehmende erfassen den Kurs in ihrem eigenen Verlauf',
			blocks: [
				{
					type: 'p',
					text: 'Auf der Kursseite sieht jede teilnehmende Person, die in ihrem Konto angemeldet ist, **Als Training erfassen**. Das öffnet einen Gym-Eintrag, der bereits nach dem Kurs benannt ist und vor dem Speichern mit eigenen Sätzen und Gewichten angepasst werden kann. Danach erscheint **Zu deinem Gym-Log hinzugefügt**, und der Kurs zählt in ihrem Trainingsverlauf wie jedes andere Training. Das funktioniert im Web und in der Handy-App.',
				},
				{
					type: 'p',
					text: 'Wer deine Routine übernommen hat, kann sie stattdessen öffnen und **Routine starten** drücken, um Satz für Satz geführt zu werden; auch diese Einheit wird im Gym-Log gespeichert.',
				},
			],
		},
		{
			heading: 'Anmeldung, der Kurstag und Änderungen',
			blocks: [
				{
					type: 'list',
					items: [
						'Teilnehmende melden sich im Web an und bezahlen dort, sehen **Du bist angemeldet** und können gemäß deiner [[guide:refund-policies|Rückerstattungsrichtlinie]] stornieren.',
						'Sind alle Plätze vergeben, steht dort **Ausverkauft** mit dem Angebot **Auf die Warteliste**: siehe [[guide:waitlist-and-claim-window|Wartelisten und die 12-Stunden-Frist]].',
						'Halte fest, wer gekommen ist: [[guide:take-attendance|Anwesenheit erfassen]].',
						'Wenn du eine Einheit absagst, bekommen alle Zahlenden ihr Geld zurück: [[guide:cancel-a-class|Einen Kurs absagen]].',
					],
				},
			],
		},
	],
};
