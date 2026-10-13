import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'build-a-gym-routine',
	source: 'ad63af66f1933ab0',
	title: 'Eine Gym-Routine erstellen',
	summary: 'Mach ein Training, das du leitest oder wiederholst, zur wiederverwendbaren Routine mit Sätzen, Wiederholungen, Gewicht, Pausen und Supersätzen, die du geführt absolvierst oder mit deinem Club teilst.',
	sections: [
		{
			heading: 'Zwei Wege zum Start',
			blocks: [
				{
					type: 'list',
					items: [
						'Von Grund auf: Öffne [[route:/gym/routines|Routinen]] und drücke **Neue Routine**. Im Web kannst du auch zu [[route:/plans/new|Neuer Plan]] gehen und **Gym-Routine** wählen.',
						'Aus einem bereits erfassten Training: Öffne es in deinem Gym-Log und drücke **Als Routine speichern**. Seine Übungen und Sätze werden zu den Zielen der Routine. **Letztes wiederholen** startet stattdessen einen neuen Eintrag aus demselben Training.',
					],
				},
				{
					type: 'p',
					text: 'Öffne in der Handy-App den Gym-Bildschirm und tippe auf **Routinen**, dann auf **Neue Routine**.',
				},
			],
		},
		{
			heading: 'Ausfüllen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Trage unter **Name der Routine** einen Namen ein, benannt nach dem Tag statt nach der ersten Übung, zum Beispiel „Bootcamp A“.',
						'Tippe den Namen der ersten Übung ein. Verwende einen Namen, den du schon erfasst, damit deine Rekorde für diese Übung an einem Ort bleiben.',
						'Wähle unter **Gemessen als**, wie sie gemessen wird: Gewicht und Wiederholungen, Körpergewicht, Zeit oder Distanz. Die Satzzeilen fragen dann das passende Ziel ab.',
						'Gib für jeden Satz einen **Satztyp** und seine Ziele an, etwa **Ziel-Wiederholungen** und Gewicht, sowie eine **Pause (s)**. Drücke **Satz hinzufügen** für weitere Sätze.',
						'Um zwei Übungen direkt hintereinander zu machen, schalte bei der ersten **Supersatz mit der nächsten Übung** ein.',
						'Drücke **Übung hinzufügen** für die nächste und wiederhole das.',
						'Öffne optional **Erweitert** und wähle eine **Progression**-Regel, die aus dem Ergebnis dieser Einheit die Werte für die nächste vorschlägt. Bleibt sie auf „Keine“, bleiben deine Ziele genau so, wie du sie eingegeben hast.',
						'Füge bei Bedarf **Notizen (optional)** hinzu und drücke **Routine speichern**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Jede Satzzeile ist ein Ziel, kein Eintrag. Damit wird eine aus der Routine gestartete Einheit vorausgefüllt, und du kannst die Werte unterwegs weiterhin ändern.',
				},
			],
		},
		{
			heading: 'Absolvieren',
			blocks: [
				{
					type: 'p',
					text: 'Öffne die Routine und drücke **Routine starten** (in der Handy-App **Einheit starten**). Du wirst Satz für Satz mit angezeigtem Ziel geführt: Erfasse, was du geschafft hast, und drücke **Satz abschließen** oder **Satz überspringen**, mit einem Pausentimer zwischen den Sätzen. Drücke am Ende **Beenden**, und die Einheit wird in deinem Gym-Log gespeichert, samt Vergleich mit dem Plan.',
				},
			],
		},
		{
			heading: 'Mit einem Kurs teilen',
			blocks: [
				{
					type: 'list',
					items: [
						'**In einem Club veröffentlichen**: Wähle den Club bei **Club auswählen…** und drücke **Veröffentlichen**. Sie erscheint im Tab **Vorlagen** dieses Clubs unter **Gym-Routine-Vorlagen**, wo Mitglieder **Übernehmen** drücken, um ihre eigene Kopie zu bekommen. Änderungen an einer Kopie ändern dein Original nicht.',
						'**In öffentlicher Bibliothek veröffentlichen**: Alle Angemeldeten können sie ansehen und übernehmen. Deine erfassten Trainings bleiben privat.',
					],
				},
				{
					type: 'p',
					text: 'Leitest du einen bezahlten Kurs rund um die Routine? Siehe [[guide:host-a-paid-gym-class|Einen bezahlten HIIT-, Kraft- oder Bootcamp-Kurs anbieten]].',
				},
			],
		},
	],
};
