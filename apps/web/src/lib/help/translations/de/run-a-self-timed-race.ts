import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'run-a-self-timed-race',
	title: 'Ein selbstgestopptes Rennen laufen',
	summary: 'Nimm an einem Rennen teil, das für einen Zeitraum offen ist, markiere deinen Lauf als deinen Versuch und lauf von der Startlinie zur Ziellinie, wann es dir passt.',
	sections: [
		{
			heading: 'Was ein selbstgestopptes Rennen ist',
			blocks: [
				{
					type: 'p',
					text: 'Ein selbstgestopptes Rennen hat keinen gemeinsamen Start. Der Veranstalter öffnet einen Zeitraum, der bis zu einer Woche dauern kann, und du läufst die Strecke, wann immer du willst, solange er offen ist. Deine Zeit läuft vom Überqueren der Startlinie bis zum Überqueren der Ziellinie, es gibt also keine Bruttozeit.',
				},
				{
					type: 'p',
					text: 'Deinen Versuch zeichnest du mit der Handy-App oder einer Wear-OS-Uhr auf. Im Web meldest du dich an und siehst Ergebnisse; ein Browser kann keinen Lauf aufzeichnen.',
				},
			],
		},
		{
			heading: 'Bevor du losläufst',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne das Renn-Event, im Web oder in der Handy-App.',
						'Gibt es mehr als eine Strecke, wähle zuerst deine.',
						'Wähle **Teilnehmen und versuchen**. Hast du schon **Ich bin dabei** gesagt, bist du bereits angemeldet.',
						'Öffne die App einmal, solange du Signal hast, bevor du losläufst. Dann kennt sie das Rennen, und das Renn-Banner und dein Versuch funktionieren auch dort, wo es kein Signal gibt.',
					],
				},
			],
		},
		{
			heading: 'Deinen Versuch starten',
			blocks: [
				{
					type: 'steps',
					items: [
						'Im Lauf-Tab der Handy-App zeigt das Renn-Banner **Selbstgestoppt** und wann der Zeitraum schließt.',
						'Tippe auf **Dieser Lauf ist mein Versuch**. Die Anzeige wechselt zu **Versuch bereit: Tippe auf Start**; tippe erneut darauf, wenn du es dir anders überlegst.',
						'Drück auf Start, bevor du die Startlinie erreichst, und lauf dann in Richtung der Strecke durch die Startlinie.',
					],
				},
				{
					type: 'p',
					text: 'Auf einer Wear-OS-Uhr zeigt der Bildschirm vor dem Start SELBSTGESTOPPT. Tippe auf **Dieser Lauf ist mein Versuch** und dann auf Start.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ein Lauf, den du nicht als deinen Versuch markierst, nimmt nie am Rennen teil: Er sendet keine Live-Position und bekommt kein Ergebnis. So landet ein Lauf, den du gar nicht als Rennen laufen wolltest, nie in der Rangliste.',
				},
			],
		},
		{
			heading: 'Versuche und dein Ergebnis',
			blocks: [
				{
					type: 'list',
					items: [
						'Du kannst mehr als einen Versuch machen, solange der Zeitraum offen ist. Tippe vor jedem auf **Dieser Lauf ist mein Versuch**.',
						'Es zählt dein bester Zieleinlauf, der über beide Linien gestoppt wurde. Ein langsamerer Versuch ersetzt ihn nicht.',
						'Dein Ergebnis wartet möglicherweise auf die Genehmigung durch den Veranstalter. Bis dahin wird es als ausstehend angezeigt und hat noch keine Platzierung.',
						'Ein Ergebnis ohne Überquerung der Startlinie, etwa eines von einer Apple Watch oder einer älteren Version der App, wird aufbewahrt, aber der Veranstalter prüft es, bevor es zählt.',
					],
				},
				{
					type: 'p',
					text: 'Was die Zeiten in der Rangliste bedeuten, steht in [[guide:race-results-explained|Rennergebnisse erklärt]].',
				},
			],
		},
		{
			heading: 'Wenn dein Handy eine Linie verpasst hat',
			blocks: [
				{
					type: 'p',
					text: 'Dein Handy oder deine Uhr sagt „Startlinie überquert, Zeitmessung läuft“, wenn es erkennt, dass du die Startlinie überquerst, und wertet deinen Zieleinlauf an der Ziellinie. Verpasst es eine davon, etwa unter Bäumen oder wenn du etwas neben der Linie startest:',
				},
				{
					type: 'list',
					items: [
						'Tippe im Ziel auf Stopp und dann auf **Rennen beenden**. Hast du 90 % der Strecke zurückgelegt, sendet das deine Zeit, und der Veranstalter prüft sie, bevor sie zählt.',
						'Oder miss deinen Versuch danach aus seinem Track neu: Öffne den Lauf im Web und wähle **Aus meinem Track neu messen**. Der Track wird anhand der Linien des Rennens gemessen und ersetzt ein Ergebnis, das auf Prüfung wartet, oder ein langsameres. Das geht bis 24 Stunden nach dem Schließen des Zeitraums.',
						'Mit einer Apple Watch gelaufen? Sie erkennt die Linien nicht, daher bekommt dein Versuch durch das Neumessen aus deinem Track ein per Linie gestopptes Ergebnis.',
					],
				},
				{
					type: 'p',
					text: 'Mehr zum Neumessen findest du in [[guide:race-results-explained|Rennergebnisse erklärt]].',
				},
			],
		},
	],
	sources: {
		title: '980e3fe539fa87ed',
		summary: '8200cb3990ca1c84',
		's0.heading': 'da16fddd6466ff82',
		's0.b0': 'b166c8e10ca64251',
		's0.b1': '9eb15ab29b32b50a',
		's1.heading': 'c682ac1a8b55d5bd',
		's1.b0.i0': 'f2699d62a364214c',
		's1.b0.i1': '15f502c0495a6810',
		's1.b0.i2': 'd67ce3877679d3b7',
		's1.b0.i3': 'd5058d744cf24c6b',
		's2.heading': '6e3e520b08e75a87',
		's2.b0.i0': '6b5b44bd7545a139',
		's2.b0.i1': '48bf3f903a530a73',
		's2.b0.i2': 'ff90c543a96100a6',
		's2.b1': '34ded6bec1fb4447',
		's2.b2': 'e9496d6a3325b124',
		's3.heading': '4ad1d4e8c17417b8',
		's3.b0.i0': 'a0858a05aad2d12a',
		's3.b0.i1': '82cda99fabf47908',
		's3.b0.i2': 'a6113125dae261a1',
		's3.b0.i3': '8e98409f10047bd7',
		's3.b1': '71fadd9d562da318',
		's4.heading': '9f401b8bc89ad9f0',
		's4.b0': 'c83ffd00a5d79eaf',
		's4.b1.i0': '371c0ea180b0a2cc',
		's4.b1.i1': 'd4b32e20b9afba25',
		's4.b1.i2': '30e86640bcd591b4',
		's4.b2': '172cd34b60d4d532',
	},
};
