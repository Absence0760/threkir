import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'set-up-a-race',
	title: 'Ein Rennen einrichten',
	summary: 'Erstelle ein Club-Event mit einer oder mehreren Strecken, damit Teilnehmende eine Distanz wählen, live gemessen werden und in einer Rangliste pro Strecke landen.',
	sections: [
		{
			heading: 'Bevor du beginnst',
			blocks: [
				{
					type: 'p',
					text: 'Ein Rennen ist ein gewöhnliches Club-Event mit angehängten Strecken. Club-Inhaber, Admins und Eventorganisatoren können Events erstellen. Für die Durchführung am Renntag (Scharfstellen, LOS, Beenden) braucht es einen Inhaber, einen Admin oder einen **Renndirektor** – siehe [[guide:race-day-for-hosts|Renntag für Veranstalter]].',
				},
				{
					type: 'p',
					text: 'Strecken werden im Web angelegt. Die Handy-App kann ein einfaches Event erstellen, hat aber keinen Strecken-Editor – füge Strecken also im Browser hinzu oder ändere sie dort.',
				},
			],
		},
		{
			heading: 'Das Event erstellen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne deinen Club und wähle **Neues Event**.',
						'Wähle unter **Veranstaltungstyp** die Option **Gruppenlauf** (oder **Radfahren**). Kurse und Treffen haben keine Route, keine Distanz, keine Rennsteuerung und keine Ergebnisse.',
						'Gib dem Event einen **Titel** und ein **Datum**. Lege eine Wiederholung nur fest, wenn das Rennen wirklich regelmäßig stattfindet; jeder Termin wird separat gelaufen.',
						'Wähle eine **Strecke** und gib die **Distanz** ein. Zusammen bilden sie deine *Hauptstrecke*.',
						'Gib optional unter **Rennstrecken** im Feld **Name der Hauptstrecke** einen Namen ein (zum Beispiel „Halbmarathon“). Lässt du das Feld leer, wird der Name der Route verwendet.',
						'Wähle **Event erstellen**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Die Ziellinie, an der die Teilnehmenden gemessen werden, ist der letzte Punkt der Route der Strecke. Zeichne die Route so, dass sie genau dort endet, wo dein Zielbogen stehen wird.',
				},
			],
		},
		{
			heading: 'Weitere Strecken hinzufügen',
			blocks: [
				{
					type: 'p',
					text: 'Werden am selben Tag mehrere Distanzen gelaufen? Füge jede zusätzliche Distanz als eigene Strecke hinzu. Jede Strecke bekommt ihre eigene Rangliste.',
				},
				{
					type: 'steps',
					items: [
						'Suche im Event-Editor **Rennstrecken** und wähle **Strecke hinzufügen**.',
						'Trag unter **Name der Strecke** einen Namen ein, wähle ihre **Route** und gib ihre Distanz ein.',
						'Mit den Pfeilen nach oben und unten änderst du die Reihenfolge der Strecken, oder du entfernst eine, die du nicht mehr brauchst.',
						'Speichere das Event.',
					],
				},
				{
					type: 'list',
					items: [
						'Jede Strecke braucht einen Namen, und keine zwei Strecken dürfen denselben haben.',
						'Eine Strecke ohne Route hat keinen Zielpunkt, daher wird der Zieleinlauf ihrer Teilnehmenden nicht automatisch gewertet; sie beenden von Hand auf ihrem Gerät.',
						'Eine Strecke ohne Distanz kann nicht prüfen, ob jemand den Großteil der Strecke zurückgelegt hat, daher beenden auch ihre Teilnehmenden von Hand.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Wenn du eine Route anhängst, wird ihr Zielpunkt allen angezeigt, die das Event sehen können, selbst wenn die Route selbst privat ist. Du kannst nur Routen anhängen, die du sehen darfst.',
				},
			],
		},
		{
			heading: 'Was Teilnehmende sehen',
			blocks: [
				{
					type: 'list',
					items: [
						'Auf der Event-Seite sehen die Teilnehmenden die Strecken. Gibt es mehr als eine, müssen sie unter **Deine Strecke** eine wählen, bevor **Ich bin dabei** funktioniert; sonst sehen sie „Wähle zuerst deine Strecke.“',
						'Tippen sie in der Handy-App bei einem Rennen mit mehreren Strecken auf **Bin dabei**, werden sie mit **Wähle deine Strecke** zur Auswahl aufgefordert und können später **Strecke ändern** nutzen.',
						'Bei nur einer Strecke muss niemand etwas auswählen.',
						'Bei kostenpflichtigen Anmeldungen wird noch nicht nach einer Strecke gefragt. Wer bezahlt hat, wählt sie anschließend im selben Menü **Deine Strecke**.',
					],
				},
				{
					type: 'p',
					text: 'Die Sicht der Teilnehmenden behandelt [[guide:racing-in-a-race|Bei einem Live-Rennen mitlaufen]].',
				},
			],
		},
		{
			heading: 'Ergebnisse automatisch genehmigen',
			blocks: [
				{
					type: 'p',
					text: 'Kurz bevor du das Rennen scharfstellst, entscheidest du, ob Ergebnisse direkt in die Rangliste kommen. **Eingereichte Ergebnisse automatisch genehmigen** ist standardmäßig angehakt. Entferne den Haken, wenn du jedes Ergebnis zuerst prüfen möchtest; jedes wird dann als **AUSSTEHEND** angezeigt, bis du es genehmigst.',
				},
			],
		},
		{
			heading: 'Den Zuschauer-Link teilen',
			blocks: [
				{
					type: 'p',
					text: 'Jeder Renntermin hat eine Live-Seite mit Karte und Listen. Auf der Event-Seite enthält die Karte der Rennsteuerung einen Link **Zuschaueransicht**, der sie in einem neuen Tab öffnet. Kopiere diese Adresse und teile sie mit Familie, Freunden und deinem Rennkanal.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Bei einem Event **Nur für Mitglieder** können nur Club-Mitglieder das Event sehen, daher funktioniert die Zuschauerseite für Personen außerhalb des Clubs nicht.',
				},
				{
					type: 'p',
					text: 'Was Zuschauer sehen, erklärt [[guide:follow-a-race-live|Ein Rennen live verfolgen]].',
				},
			],
		},
	],
	sources: {
		title: '9c550364ef27a6b1',
		summary: '366fcefd4c4d302c',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': 'e59685e187f9a957',
		's0.b1': '6109c712395ba1b9',
		's1.heading': 'bdd2bbbddd9c3cf5',
		's1.b0.i0': 'ad4d295ffcc8f3a0',
		's1.b0.i1': '6f2498dc63953e9d',
		's1.b0.i2': '1de2284a85b9b8d0',
		's1.b0.i3': '66dae8991279459e',
		's1.b0.i4': '5dc3211a9d733e18',
		's1.b0.i5': '9b013cf91adfef1d',
		's1.b1': '4dedb854832fabbb',
		's2.heading': 'aa02687fee3b093f',
		's2.b0': '1e44be9c1cbe6aa5',
		's2.b1.i0': '59ec7388c26ff153',
		's2.b1.i1': '7e55782eb49cd9f2',
		's2.b1.i2': 'b71f0dd3bc7d65dd',
		's2.b1.i3': 'e70bf0579a469363',
		's2.b2.i0': 'd37d68f01d59d140',
		's2.b2.i1': '614d8a4a47ff46c0',
		's2.b2.i2': '6ba6f0661b9e166a',
		's2.b3': '47950903add3bde2',
		's3.heading': '8b4ed9e415e501f7',
		's3.b0.i0': '7366e2c6f9eafeb3',
		's3.b0.i1': '76dc29eb1e584662',
		's3.b0.i2': '295fb740c0b19c57',
		's3.b0.i3': 'f12d86e7aff3dc0e',
		's3.b1': 'd636d4186f153c0f',
		's4.heading': 'ff04ee128bd05b1f',
		's4.b0': '8887aff2546f155b',
		's5.heading': '05127d2bcbe7e55c',
		's5.b0': '632ca275dd6dbc2e',
		's5.b1': 'd81f08a86fd29b85',
		's5.b2': '7375e2668380d4e1',
	},
};
