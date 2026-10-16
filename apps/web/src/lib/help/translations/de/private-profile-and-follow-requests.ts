import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'private-profile-and-follow-requests',
	title: 'Dein Profil privat machen und Follower annehmen',
	summary: 'Schalte ein privates Profil ein, damit nur Follower, die du annimmst, deine Läufe sehen, und nimm Follower-Anfragen an oder lehne sie ab, sobald sie eintreffen.',
	sections: [
		{
			heading: 'Was ein privates Profil verbirgt',
			blocks: [
				{
					type: 'p',
					text: 'Bei einem privaten Profil sehen nur Follower, die du angenommen hast, deine Läufe und anderen Aktivitäten sowie die Listen, wer dir folgt und wem du folgst. Alle anderen sehen deinen Namen, dein Bild und deine Follower-Zahlen und an der Stelle deiner Läufe **Dieses Profil ist privat**.',
				},
				{
					type: 'list',
					items: [
						'Andere können dich weiterhin über deinen Namen finden und anfragen, dir zu folgen. Wenn du auch nicht in der Namenssuche erscheinen willst, schalte auf derselben Seite **Mich in der Namenssuche anzeigen** aus.',
						'Wer dir schon folgt, wenn du es einschaltest, folgt dir weiterhin.',
						'Routen, Event-Ergebnisse und Abzeichen behalten ihre eigene Sichtbarkeit, weil jedes davon einzeln geteilt wird.',
						'Ein Live-Link, den du während eines Laufs verschickst, auch der Link in einem Sicherheitsalarm, funktioniert für die Empfänger weiterhin.',
					],
				},
			],
		},
		{
			heading: 'Einschalten',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne im Web in den Einstellungen [[route:/settings/privacy|Datenschutz & Teilen]] und hake unter **Gefunden werden** die Option **Privates Profil** an.',
						'Öffne in der Handy-App **Voreinstellungen** im Tab **Du** und schalte unter **Datenschutz & Teilen** die Option **Privates Profil** ein.',
					],
				},
				{
					type: 'p',
					text: 'Die Änderung wird sofort gespeichert.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Schaltest du es wieder aus, werden alle noch offenen Anfragen angenommen, und diese Personen folgen dir sofort.',
				},
			],
		},
		{
			heading: 'Anfragen annehmen oder ablehnen',
			blocks: [
				{
					type: 'p',
					text: 'Wenn jemand anfragt, dir zu folgen, bekommst du eine Benachrichtigung. Follower-Anfragen gelten als wichtig, daher bekommst du sie standardmäßig auch per E-Mail und Push.',
				},
				{
					type: 'steps',
					items: [
						'Öffne die Benachrichtigung. Du kannst auch im Web unter **Privates Profil** die Option **Follower-Anfragen ansehen** wählen oder in der Handy-App unter **Privates Profil** auf **Follower-Anfragen** tippen.',
						'Wähle **Annehmen**, damit die Person dein Profil sehen kann, oder **Ablehnen**, um die Anfrage abzulehnen. Bei einer Ablehnung wird sie nicht benachrichtigt.',
					],
				},
			],
		},
		{
			heading: 'Jemandem mit privatem Profil folgen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne das Profil und wähle **Folgen anfragen**.',
						'Solange du wartest, zeigt die Schaltfläche **Angefragt**. Wähle sie erneut, um die Anfrage zurückzuziehen.',
						'Sobald die Person annimmt, zeigt die Schaltfläche **Folgt**, und die Läufe erscheinen.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Wenn du jemandem mit privatem Profil entfolgst, musst du erneut anfragen, um die Läufe zu sehen.',
				},
			],
		},
	],
	sources: {
		title: '55db0776dec72032',
		summary: 'e6bdb709c41db3db',
		's0.heading': '7237eeb5591555f6',
		's0.b0': '7c2c985869ef044e',
		's0.b1.i0': '46be0ce6681dea88',
		's0.b1.i1': 'a724eac62d2e2309',
		's0.b1.i2': 'ab64bd2163f3b938',
		's0.b1.i3': '3b0697b82ce30a11',
		's1.heading': 'e679ca0953315c31',
		's1.b0.i0': '8f81f66ef4f33b7f',
		's1.b0.i1': 'a2257970d4c18f57',
		's1.b1': '0a095b7bf566bcfd',
		's1.b2': 'ad288ebf5f9c8856',
		's2.heading': '93f13a5ed9bf1a93',
		's2.b0': 'd2a27163d9554bb2',
		's2.b1.i0': '2ed84578bbbb7b5f',
		's2.b1.i1': '6d2ff83c41b08bdc',
		's3.heading': '185850fe604d3b78',
		's3.b0.i0': 'd39f871565375e15',
		's3.b0.i1': 'd9de093774b97d75',
		's3.b0.i2': 'e44b708377c7377a',
		's3.b1': '6f8889c46cf20f3c',
	},
};
