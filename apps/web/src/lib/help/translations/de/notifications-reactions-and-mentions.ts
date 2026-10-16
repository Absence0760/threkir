import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'notifications-reactions-and-mentions',
	title: 'Reaktionen, Erwähnungen und deine Benachrichtigungen',
	summary: 'Reagiere auf Läufe, markiere Kommentare mit „Gefällt mir“ und erwähne andere Läufer, und lege dann fest, welche Benachrichtigungen dich auch per E-Mail und auf dem Handy erreichen.',
	sections: [
		{
			heading: 'Reagieren, liken und erwähnen',
			blocks: [
				{
					type: 'list',
					items: [
						'Wähle beim Lauf eines anderen neben den Kudos eine Reaktion: **Stark unterwegs**, **Kraftvoll**, **Meisterhaft**, **Gut gemacht** oder **Hallo**. Du kannst mehrere hinterlassen, und ein erneutes Wählen nimmt eine Reaktion zurück.',
						'Um einen Kommentar mit „Gefällt mir“ zu markieren, wähle das Herz daneben. Auf deinen eigenen Lauf kannst du nicht reagieren, und deinen eigenen Kommentar kannst du nicht liken.',
						'Um jemanden in einem Kommentar zu erwähnen, tippe @ und den Anfang des Namens und wähle die Person aus der Liste, die erscheint. Sie wird nur benachrichtigt, wenn sie den Lauf ohnehin sehen kann und keiner von euch den anderen blockiert hat.',
					],
				},
				{
					type: 'p',
					text: 'Reaktionen und „Gefällt mir“ für Kommentare werden beim Lauf selbst angezeigt. Karten im Feed zeigen weiterhin nur die Zahl der Kudos und Kommentare.',
				},
			],
		},
		{
			heading: 'Wo Benachrichtigungen erscheinen',
			blocks: [
				{
					type: 'p',
					text: 'Jede Benachrichtigung landet in der App: unter der Glocke im Web und im Tab **Mitteilungen** deines Profils in der Handy-App. Ob sie dich auch per E-Mail oder auf dem Handy erreicht, entscheidest du.',
				},
			],
		},
		{
			heading: 'Festlegen, was per E-Mail und Push kommt',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne im Web in den Einstellungen [[route:/settings/notifications|Benachrichtigungen]]. Öffne in der Handy-App **Voreinstellungen** im Tab **Du** und scrolle zu **Benachrichtigungen**.',
						'Stelle **E-Mail-Benachrichtigungen** und **Push-Benachrichtigungen** getrennt ein.',
					],
				},
				{
					type: 'list',
					items: [
						'**Nur wichtige**, die Standardeinstellung: Dinge, auf die du wartest oder die deine Pläne ändern, etwa Nachrichten, Event-Erinnerungen und -Absagen, ein für dich reservierter Platz auf einer Warteliste, Erwähnungen, Follower-Anfragen und ein fertiger Datenexport.',
						'**Alle**: die wichtigen plus die sozialen, etwa Kudos, Kommentare, neue Follower, Reaktionen und „Gefällt mir“ für Kommentare.',
						'**Aus**: nichts über diesen Kanal. Die App zeigt trotzdem alles.',
					],
				},
			],
		},
		{
			heading: 'Eine einzelne Art abschalten',
			blocks: [
				{
					type: 'p',
					text: 'Im Web kannst du auf derselben Seite einige Arten stummschalten, ohne einen ganzen Kanal zu ändern: **Datenexport fertig**, **Erwähnungen**, **Reaktionen auf meine Läufe**, **„Gefällt mir“ für meine Kommentare** und **Follower-Anfragen**. Nimmst du bei einer das Häkchen heraus, kommt sie nicht mehr per E-Mail und Push, auch nicht auf dem Handy, erscheint aber weiterhin in der App.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Diese Schalter schalten nur ab. Reaktionen und „Gefällt mir“ für Kommentare werden nur verschickt, wenn ein Kanal auf **Alle** steht, und ein Kanal auf **Aus** bleibt still, egal wie die Schalter stehen.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Die Schalter für einzelne Arten gibt es vorerst nur im Web. Die Handy-App zeigt die Einstellungen für E-Mail und Push.',
				},
			],
		},
	],
	sources: {
		title: 'e2dd210eef629161',
		summary: 'e3caa3dd4051e339',
		's0.heading': 'e9a0aa732a34f472',
		's0.b0.i0': '593bf97b7d4b2620',
		's0.b0.i1': '47c9a6dbdeb3921f',
		's0.b0.i2': '3f6f5a25189cef93',
		's0.b1': 'a9ec227602fcdf51',
		's1.heading': '074e9ceb824efc1f',
		's1.b0': '93884f29ad0c80fc',
		's2.heading': 'effb878df9e1a9ea',
		's2.b0.i0': '1c0dfd20d4a186e9',
		's2.b0.i1': '5a887c760fb14d6f',
		's2.b1.i0': '3adf3c1bbb3ad28d',
		's2.b1.i1': '20670a8e203c8f76',
		's2.b1.i2': '0e68d1c319340628',
		's3.heading': '99fb6c0af9167c4d',
		's3.b0': 'f6afa349950bc135',
		's3.b1': '17f7f798ca3f2b0d',
		's3.b2': '7471f8039fdd65e1',
	},
};
