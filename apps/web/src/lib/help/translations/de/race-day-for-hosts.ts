import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-day-for-hosts',
	title: 'Renntag für Veranstalter',
	summary: 'Schalte das Rennen scharf, gib GO, verfolge es live, beende es und genehmige und korrigiere dann die Ergebnisse.',
	sections: [
		{
			heading: 'Wer ein Rennen leiten kann',
			blocks: [
				{
					type: 'p',
					text: 'Die Rennsteuerung erscheint auf der Event-Seite für Club-Inhaber, Admins und Mitglieder mit der Rolle **Renndirektor**. Im Web ist es die Karte **Rennsteuerung**, in der Handy-App die Karte **RENNSTEUERUNG** auf dem Event-Bildschirm. In beiden kannst du Ergebnisse genehmigen und bearbeiten.',
				},
				{
					type: 'p',
					text: 'Sorge zuerst dafür, dass das Event Strecken hat – siehe [[guide:set-up-a-race|Ein Rennen einrichten]].',
				},
				{
					type: 'illustration',
					id: 'race-day-for-hosts',
					alt: 'Der Renntag in vier Schritten von links nach rechts: das Rennen scharf schalten, GO geben, live verfolgen und es dann im Ziel beenden.',
				},
				{
					type: 'p',
					text: 'Diese Schritte gelten für ein Rennen im Modus **GO durch Veranstalter**. Ein Rennen im Modus **Geplanter GO** startet von selbst, und ein **Selbstgestoppter Zeitraum** braucht am Renntag nichts von dir; siehe [[guide:choose-how-your-race-starts|Festlegen, wie dein Rennen startet]].',
				},
			],
		},
		{
			heading: '1. Rennen scharf schalten',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne das Event und wähle den heutigen Termin, falls es sich wiederholt.',
						'Lass **Eingereichte Ergebnisse automatisch genehmigen** angehakt, um Ergebnisse bei Eingang zu veröffentlichen, oder entferne den Haken, um jedes selbst zu genehmigen. (In der Handy-App heißt es **Eingereichte Zeiten automatisch genehmigen**.)',
						'Wähle **Rennen scharf schalten**, wenn alle versammelt sind.',
					],
				},
				{
					type: 'p',
					text: 'Teilnehmende, die **Ich bin dabei** gesagt haben, sehen jetzt **Rennen bereit** im Lauf-Tab ihres Handys und „RENNEN BEREIT“ auf ihrer Wear-OS-Uhr.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Ein scharf geschaltetes Rennen wartet nur: Es wird nichts gemessen, und es können keine Ergebnisse gespeichert werden, bis du GO gibst.',
				},
				{
					type: 'p',
					text: 'Bevor das Rennen scharf geschaltet wird, werden die Start- und Ziellinien jeder Strecke geprüft, und alles, was einen Blick wert ist, steht unter **Bevor du das Rennen scharf schaltest**. Bei einer Warnung kannst du **Trotzdem scharf schalten**; siehe [[guide:start-and-finish-lines|Start- und Ziellinien]]. Das Scharfschalten friert außerdem die Linien für dieses Rennen ein.',
				},
			],
		},
		{
			heading: '2. GO geben',
			blocks: [
				{
					type: 'p',
					text: 'Drücke im Web oder in der Handy-App auf **GO**, genau in dem Moment, in dem das Rennen startet.',
				},
				{
					type: 'p',
					text: 'Die Startzeit wird von unserem Server gestempelt, nicht von deinem Gerät. So gilt für alle Teilnehmenden derselbe GO-Zeitpunkt, auch wenn die Uhr deines Handys ein paar Sekunden abweicht. Die Bruttozeit aller Teilnehmenden wird ab diesem Moment gemessen.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'GO startet bei niemandem die Aufzeichnung. Die Teilnehmenden drücken selbst auf Start auf ihrem Handy oder ihrer Uhr, entweder an der Startlinie, während das Rennen scharf geschaltet ist (die Aufzeichnung wird bei GO mit dem Rennen verknüpft), oder nachdem sie **Rennen LIVE** sehen. Erinnere sie daran, eine Aufzeichnung zu starten.',
				},
			],
		},
		{
			heading: '3. Live verfolgen',
			blocks: [
				{
					type: 'list',
					items: [
						'Die Karte der Rennsteuerung zeigt **Läuft** mit der verstrichenen Zeit.',
						'Wähle **Zuschaueransicht** für die Live-Karte, die Liste **Auf der Strecke** und die Liste **Beendet**. Siehe [[guide:follow-a-race-live|Ein Rennen live verfolgen]].',
						'Die Geräte der Teilnehmenden werten den Zieleinlauf an der Ziellinie automatisch, sodass Ergebnisse auf der Event-Seite erscheinen, während das Rennen noch läuft.',
					],
				},
			],
		},
		{
			heading: '4. Rennen beenden',
			blocks: [
				{
					type: 'steps',
					items: [
						'Wenn die letzten Teilnehmenden im Ziel sind (oder dein Zielschluss vorbei ist), wähle **Rennen beenden**.',
						'Die Bestätigung zeigt dir im Web und in der Handy-App, wie viele gestartete Teilnehmende kein Ergebnis haben. Diese Teilnehmenden werden als DNF markiert.',
						'Bestätige mit **Rennen beenden**.',
					],
				},
				{
					type: 'p',
					text: 'Beim Beenden wird für alle Teilnehmenden, die mindestens eine Live-Position gesendet, aber kein Ergebnis haben, ein DNF eingetragen, mit Distanz und Zeit ihrer letzten Position. Diese DNFs tragen die Veranstalter-Kennzeichnung. Für Teilnehmende, die nie eine Aufzeichnung gestartet haben, wird nichts eingetragen.',
				},
				{
					type: 'p',
					text: 'Wessen Handy oder Uhr im Ziel kein Signal hatte, kann bis zu 24 Stunden nach dem Beenden des Rennens noch ein zwischengespeichertes Ergebnis senden; es ersetzt dann das DNF.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Das Beenden kann nicht rückgängig gemacht werden. Danach erwarten die Geräte der Teilnehmenden kein Ergebnis mehr. Um denselben Termin erneut zu laufen, schalte eine neue Sitzung scharf.',
				},
			],
		},
		{
			heading: 'Absagen',
			blocks: [
				{
					type: 'p',
					text: 'Du kannst nur absagen, solange das Rennen scharf geschaltet ist: Wähle **Abbrechen** neben **GO** und dann **Rennen abbrechen**. Sobald du GO gegeben hast, kann das Rennen nur noch beendet werden.',
				},
				{
					type: 'p',
					text: 'Beim Absagen werden keine DNFs eingetragen. Die Zuschauerseite zeigt an, dass der Veranstalter das Rennen abgesagt hat, und die Teilnehmenden sehen, dass das Rennen beendet ist.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Das Absagen kann nicht rückgängig gemacht werden. Nutze stattdessen **Rennen beenden**, wenn tatsächlich gelaufen wurde und du die Ergebnisse haben möchtest.',
				},
			],
		},
		{
			heading: 'Ergebnisse genehmigen und bearbeiten',
			blocks: [
				{
					type: 'p',
					text: 'Die Ergebnisse stehen auf der Event-Seite unter **Ergebnisse**, mit einer Liste pro Strecke. In der Handy-App hat jedes Ergebnis ein Menü mit denselben Aktionen **Genehmigen**, **Verifizierung aufheben** und **Bearbeiten**.',
				},
				{
					type: 'list',
					items: [
						'War die automatische Genehmigung aus, zeigen neue Ergebnisse **AUSSTEHEND** und keinen Platz. Wähle **Genehmigen**, um eines zu veröffentlichen. **Verifizierung aufheben** setzt ein genehmigtes Ergebnis wieder auf ausstehend.',
						'Um ein Ergebnis zu korrigieren, wähle **Bearbeiten**, gib eine **Zeit (h:mm:ss)** und einen **Status** (**Im Ziel**, **DNF** oder **DNS**) ein und wähle dann **Ergebnis speichern**.',
						'Ein bearbeitetes Ergebnis wird als **Vom Veranstalter bearbeitet** markiert, damit alle sehen, dass der Veranstalter es geändert hat. Die Änderung verschiebt auch die Bruttozeit der teilnehmenden Person.',
						'**Ergebnisse als CSV herunterladen** exportiert die Listen.',
					],
				},
				{
					type: 'p',
					text: 'Bei einem selbstgestoppten Rennen warten Ergebnisse standardmäßig auf deine Genehmigung, und manche werden auch bei aktiver automatischer Genehmigung zur Prüfung zurückgehalten. Siehe [[guide:choose-how-your-race-starts|Festlegen, wie dein Rennen startet]].',
				},
			],
		},
	],
	sources: {
		title: '345bfeb73c862a63',
		summary: '68e18b9d83f2ca2d',
		's0.heading': '95b8e6a62cefca57',
		's0.b0': '7b081f765b2e73ec',
		's0.b1': '00aa52e26fec65b0',
		's0.b2': '043bfb92b5287252',
		's0.b3': 'acc54eca742d3a9e',
		's1.heading': '0f3300a60c9bfa0b',
		's1.b0.i0': '7bdfd19fafd16a95',
		's1.b0.i1': 'b26a53d0fd770ca6',
		's1.b0.i2': 'db729ba4238dbf0f',
		's1.b1': '94ec2fea3c0890dc',
		's1.b2': '9b4a5aa61857cac1',
		's1.b3': 'e8bb5e75119028d9',
		's2.heading': 'bcda14674f57c276',
		's2.b0': '7d9717e613d837c4',
		's2.b1': '656cb122eaf287fc',
		's2.b2': '65fce2c1be98450f',
		's3.heading': 'c3c4743c28e9dcc0',
		's3.b0.i0': 'aa6bba561bc42aea',
		's3.b0.i1': 'b8ecf8f3f5af1006',
		's3.b0.i2': '9874c56b87143c5f',
		's4.heading': '14dea53ae562634f',
		's4.b0.i0': '4bb0c3a5ddf2738a',
		's4.b0.i1': '9f2d97f9ea8e9cdf',
		's4.b0.i2': 'e63d194b0818af24',
		's4.b1': 'd9f0c880b9265d6c',
		's4.b2': 'eefbd14c075fb596',
		's4.b3': 'b067bfb6142d262b',
		's5.heading': '20d55e8c3373cb09',
		's5.b0': '262e1b926341a0a0',
		's5.b1': 'ba1729be79f60bc4',
		's5.b2': 'b10fb4196bd3e2ef',
		's6.heading': '27e65c3d7a252fc5',
		's6.b0': '982210c986719645',
		's6.b1.i0': 'a0e615efe581a71e',
		's6.b1.i1': '0bada1dfb7752ded',
		's6.b1.i2': 'dc555607c15c1ae0',
		's6.b1.i3': '12b5ecdf863972b3',
		's6.b2': 'f2d0c11bca104665',
	},
};
