import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'choose-how-your-race-starts',
	title: 'Festlegen, wie dein Rennen startet',
	summary: 'GO durch Veranstalter, Geplanter GO oder Selbstgestoppter Zeitraum: wann du welche Art nutzt, was du am Renntag tust und wie Ergebnisse genehmigt werden.',
	sections: [
		{
			heading: 'Drei Arten zu starten',
			blocks: [
				{
					type: 'list',
					items: [
						'**GO durch Veranstalter**: Du stellst das Rennen scharf und drückst an der Linie auf GO. Nutze das, wenn du mit allen am Start bist, für einen Massenstart.',
						'**Geplanter GO**: Das Rennen startet zur eingestellten Zeit von selbst. Nutze das, wenn die Startzeit feststeht, du aber vielleicht nicht an der Linie bist oder selbst mitlaufen möchtest. Bis dahin kannst du den Start verschieben oder das Rennen absagen.',
						'**Selbstgestoppter Zeitraum**: Es gibt keinen gemeinsamen Start. Alle stoppen ihren eigenen Versuch zwischen Startlinie und Ziellinie, jederzeit, solange der Zeitraum offen ist. Nutze das für einen wöchentlichen Zeitlauf oder eine Strecke, die man läuft, wann man kann. Es gibt keine Bruttozeit.',
					],
				},
				{
					type: 'p',
					text: 'Die Wahl triffst du unter **Wie das Rennen startet** im Event-Editor im Web, bei einem Gruppenlauf- oder Radfahr-Event. Die Handy-App kann das Rennen am Renntag leiten (früher scharfstellen, verschieben, verlängern oder beenden), aber die Startart wird im Web gewählt.',
				},
			],
		},
		{
			heading: 'Die Zeiten festlegen',
			blocks: [
				{
					type: 'list',
					items: [
						'Geplanter GO: Lege **Startzeit** und **Starttag** fest (am Tag des Events, am Vortag oder am Tag danach). Unter **Endet nach, Tage** und **Stunden** legst du fest, wie lange nach GO das Rennen von selbst endet, außer du beendest es vorher.',
						'Selbstgestoppter Zeitraum: Lege **Zeitraum öffnet um** und **Öffnet am** fest (vom Tag vor dem Event bis eine Woche danach) und unter **Dauer des Zeitraums, Tage** und **Stunden**, wie lange er offen bleibt, von 1 Minute bis 7 Tagen.',
					],
				},
				{
					type: 'p',
					text: 'Du gibst die Zeiten nach der Uhr des Events ein und siehst sie auch so, in seiner Zeitzone. Auf der Event-Seite zeigt der Rennbereich diese Zeitzone und, wenn deine abweicht, daneben deine eigene Uhrzeit.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Die Zeiten gelten relativ zu jedem Termin des Events. Verschiebst du das Event oder einen seiner Termine, wandern die Rennzeiten mit. Änderst du die Zeiten im Editor, übernimmt jeder Termin, der noch nicht begonnen hat, die neuen Zeiten.',
				},
			],
		},
		{
			heading: 'Am Renntag: GO durch Veranstalter',
			blocks: [
				{
					type: 'p',
					text: 'Du stellst das Rennen scharf, gibst GO und beendest es selbst. Siehe [[guide:race-day-for-hosts|Renntag für Veranstalter]].',
				},
			],
		},
		{
			heading: 'Am Renntag: Geplanter GO',
			blocks: [
				{
					type: 'list',
					items: [
						'Du musst nichts tun. Das Rennen wird etwa einen Tag vor dem Start angelegt und startet zur geplanten Zeit von selbst.',
						'Um die Linien der Strecken früher zu prüfen, wähle **Früher scharfstellen**.',
						'Vor dem Start zeigt der Rennbereich **Start um** mit der Uhrzeit und einem Countdown. Um den Start nach hinten zu verschieben, gib die Minuten ein und wähle **Start verschieben**; alle, die dabei sind, erfahren, dass der Start verschoben wurde. Wähle **Abbrechen**, um das Rennen abzusagen.',
						'Sobald die Startzeit vorbei ist, kann das Rennen nicht mehr abgesagt werden. Es endet von selbst, wenn seine Zeit abgelaufen ist, oder du wählst **Rennen beenden**, um es früher zu beenden.',
						'Die Handys der Teilnehmenden zählen nach der Serveruhr bis zum Start herunter und sagen die letzten Sekunden an, sodass alle gemeinsam starten.',
					],
				},
			],
		},
		{
			heading: 'Am Renntag: Selbstgestoppt',
			blocks: [
				{
					type: 'list',
					items: [
						'Es gibt nichts zu drücken. Der Zeitraum öffnet und schließt sich von selbst.',
						'Bevor er öffnet, kannst du wie bei einem geplanten Rennen **Start verschieben** oder **Abbrechen** wählen.',
						'Solange er offen ist, gib die Stunden ein und wähle **Zeitraum verlängern**, um ihn länger offen zu halten (bis zu 7 Tage ab dem Öffnen), oder wähle **Zeitraum jetzt beenden**, um ihn früher zu schließen.',
						'Schließt der Zeitraum, wird jemand, der einen Versuch begonnen, aber kein Ergebnis gesendet hat, als DNF markiert, wie beim Beenden jedes Rennens.',
					],
				},
				{
					type: 'p',
					text: 'Jede Strecke braucht eine Startlinie und eine Ziellinie, und sie werden für das Rennen eingefroren, wenn der Zeitraum öffnet. Siehe [[guide:start-and-finish-lines|Start- und Ziellinien]].',
				},
			],
		},
		{
			heading: 'Selbstgestoppte Ergebnisse genehmigen',
			blocks: [
				{
					type: 'p',
					text: 'Bei einem selbstgestoppten Rennen steht niemand an der Linie, daher warten seine Ergebnisse standardmäßig auf dich: **Eingereichte Ergebnisse automatisch genehmigen** ist anfangs aus. Jedes Ergebnis zeigt **AUSSTEHEND**, bis du **Genehmigen** wählst.',
				},
				{
					type: 'p',
					text: 'Manche Ergebnisse werden auch bei aktiver automatischer Genehmigung zur Prüfung zurückgehalten: eines ohne Überquerung der Startlinie (aus einer älteren App oder von einer Apple Watch), eines, das außerhalb des Zeitraums beginnt, und eines, dessen Überquerungen die eigenen Live-Positionen der teilnehmenden Person nicht bestätigen. Ändert jemand die eigene Zeit, ist das Ergebnis ebenfalls wieder ausstehend.',
				},
				{
					type: 'p',
					text: 'Teilnehmende können mehrere Versuche machen. Es zählt ihr bester Zieleinlauf, der über beide Linien gestoppt wurde, und ein langsamerer Versuch ersetzt ihn nicht.',
				},
			],
		},
		{
			heading: 'Hinweise zum baldigen Start',
			blocks: [
				{
					type: 'p',
					text: 'Etwa 10 Minuten vor einem geplanten GO erhalten alle, die dabei sind, eine Push-Benachrichtigung, dass das Rennen bald startet, außer sie haben in der letzten Stunde schon eine Event-Erinnerung bekommen. Wenn du einen Start verschiebst, bekommen sie eine, die ihnen das mitteilt. Diese Hinweise werden nie per E-Mail verschickt.',
				},
				{
					type: 'p',
					text: 'Teilnehmende schalten beide mit **Rennen startet bald** aus: im Web unter [[route:/settings/notifications|Benachrichtigungen]], in der Handy-App unter **Voreinstellungen** im Tab **Du**.',
				},
			],
		},
		{
			heading: 'Teilnehmende brauchen eine aktuelle App',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Geplante und selbstgestoppte Rennen brauchen die neueste App auf dem Handy oder der Wear-OS-Uhr. Ergebnisse aus älteren Apps und von der Apple Watch werden zu deiner Prüfung aufbewahrt statt abgelehnt.',
				},
			],
		},
	],
	sources: {
		title: '8dd0bfbefd97b39d',
		summary: '5f79511dd816ce5e',
		's0.heading': '9b26470e1beae1e9',
		's0.b0.i0': '653b79ec7d550dc5',
		's0.b0.i1': '6824deac8c3239bb',
		's0.b0.i2': '86642ad5f00798d9',
		's0.b1': '8ec9d026a8e162d9',
		's1.heading': '8ec1ca546316bf44',
		's1.b0.i0': '7f4cdf51f946ad7a',
		's1.b0.i1': 'e945e787986a825b',
		's1.b1': 'dc8ad2296857c406',
		's1.b2': 'f73aee6a8e52f86d',
		's2.heading': '3b72a06be5feeca1',
		's2.b0': 'f8eb6df29239da40',
		's3.heading': '2e53337b73ea8f70',
		's3.b0.i0': '0cd2e7973bd13122',
		's3.b0.i1': 'bb292e4077fab06b',
		's3.b0.i2': '1001bcee9a695cbd',
		's3.b0.i3': 'ad3f370a0b11c0ea',
		's3.b0.i4': '8469b5a684fd410f',
		's4.heading': '5b67193948e22e2a',
		's4.b0.i0': '689b27335b1205f7',
		's4.b0.i1': '8835ede766aaa683',
		's4.b0.i2': '92ab0d9a0804d8f9',
		's4.b0.i3': 'fe1797aedc22317e',
		's4.b1': 'fe8c69f32f52d3b4',
		's5.heading': '32e61b0e9e8b093c',
		's5.b0': 'd72ed9b7c3434bf2',
		's5.b1': '8270611445444242',
		's5.b2': '80fde57d63447dcd',
		's6.heading': 'b0f6668439cdc509',
		's6.b0': '7f18ce5f91bea911',
		's6.b1': '125e56f45585f84e',
		's7.heading': '81f746d1e62c98a8',
		's7.b0': '00727d27f2897451',
	},
};
