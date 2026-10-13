import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'take-attendance',
	source: '2db822cc90717a7a',
	title: 'Anwesenheit bei einem Kurs erfassen',
	summary: 'Halte fest, wer zu jedem Termin eines Kurses tatsächlich gekommen ist, getrennt davon, wer zugesagt hat – im Web oder in der Handy-App.',
	sections: [
		{
			heading: 'Wer sie erfassen kann und wo',
			blocks: [
				{
					type: 'p',
					text: 'Anwesenheit gibt es für Events vom Typ **Kurs**, und nur die Admins und Eventorganisatoren des Clubs können sie erfassen. Sie funktioniert im Web und in der Handy-App gleich, du kannst sie also vorne im Raum auf deinem Handy erfassen.',
				},
				{
					type: 'p',
					text: 'Sie ist unabhängig von der Zusage. Jemand kann **Zugesagt** sein oder angemeldet und bezahlt und trotzdem als nicht erschienen markiert werden; das Erfassen der Anwesenheit ändert nie die Anmeldung und erstattet niemandem etwas.',
				},
			],
		},
		{
			heading: 'Festhalten, wer gekommen ist',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne den Kurs. Wiederholt er sich, wähle mit **Termin auswählen** das heutige Datum, denn die Anwesenheit wird pro Termin erfasst.',
						'Scrolle zur Teilnehmerliste.',
						'Drücke neben jeder Person **Als teilgenommen markieren** oder **Als nicht erschienen markieren**.',
						'Falsch gedrückt? Drücke denselben Button noch einmal, um die Markierung zu entfernen.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Du musst nicht alle markieren. Für alle, die unmarkiert bleiben, ist einfach keine Anwesenheit erfasst.',
				},
			],
		},
		{
			heading: 'Was andere sehen',
			blocks: [
				{
					type: 'p',
					text: 'Andere, die sich den Kurs ansehen, sehen neben jedem markierten Namen ein Label **Teilgenommen** oder **Nicht erschienen**, können es aber nicht ändern.',
				},
				{
					type: 'p',
					text: 'Die Anwesenheit trägt den Kurs nicht in den Trainingsverlauf ein. Das machen Teilnehmende selbst mit **Als Training erfassen** auf der Kursseite oder indem sie dem Session-Plan des Kurses folgen: siehe [[guide:build-a-session-plan|Einen Session-Plan erstellen]].',
				},
			],
		},
	],
};
