import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'take-attendance',
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
	sources: {
		title: '8e94f2c520c4725e',
		summary: '19234d07e67c5a4f',
		's0.heading': 'faee9310c256dbe3',
		's0.b0': 'f196a1f6af265a97',
		's0.b1': '4e5ee5d97f6345cd',
		's1.heading': '606dabb8e1030b7c',
		's1.b0.i0': 'd74050897fbc9e6d',
		's1.b0.i1': '2d151dfb1f62d0b0',
		's1.b0.i2': 'aee700bc763c5ade',
		's1.b0.i3': '3222de96fadf77f6',
		's1.b1': '1ca4fbd7f7608965',
		's2.heading': '7e87e01018106f7c',
		's2.b0': '83dbaf9e7ca920df',
		's2.b1': '1195e880106739dc',
	},
};
