import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'build-a-session-plan',
	title: 'Einen Session-Plan für Yoga, Pilates oder Mobility erstellen',
	summary: 'Schreib eine zeitgesteuerte Abfolge aus Haltepositionen, Flows und Wiederholungen mit Bewegungen pro Seite und Hinweisen, unterrichte damit, häng sie an einen Kurs und mach mit.',
	sections: [
		{
			heading: 'Wo du ihn erstellst',
			blocks: [
				{
					type: 'p',
					text: 'Session-Pläne werden im Web geschrieben. Die Handy-App listet sie auf und spielt sie ab, hat aber noch keinen Editor.',
				},
				{
					type: 'list',
					items: [
						'Für dich selbst: Öffne [[route:/plans/new|Neuer Plan]] und wähle **Session-Plan**, oder drücke **Neue Session** unter [[route:/sessions|Sessions]].',
						'Für deinen Club: Drücke im Tab **Vorlagen** des Clubs auf **Vorlage hinzufügen** und wähle **Session-Plan**. Er wird sofort als Club-Vorlage gespeichert.',
					],
				},
			],
		},
		{
			heading: 'Ausfüllen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Gib ihm einen **Titel**, der die Abfolge benennt, etwa „Hüftöffner-Flow, 45 Min.“.',
						'Füge eine **Disziplin** hinzu (zum Beispiel Vinyasa-Yoga) und die **Ausrüstung**, die bereitliegen sollte, etwa eine Matte oder einen Reformer.',
						'Drücke optional **Block hinzufügen**, um den Plan in Abschnitte wie Aufwärmen, Stehende Haltungen und Abkühlen zu gliedern. Ein Plan ohne Blöcke läuft am Stück durch.',
						'Drücke für jede Haltung oder Übung **Bewegung hinzufügen** und tippe ihren Namen unter **Bewegung** ein.',
						'Wähle ihre **Art**: **Halten** für eine zeitgesteuerte Haltung, **Flow** für eine zeitgesteuerte Bewegungsfolge oder **Wdh.** für eine gezählte Übung. Gib dann **Sekunden** oder **Wiederholungen** ein und den **Block**, zu dem sie gehört.',
						'Hake **Pro Seite (links & rechts)** für alles an, was auf jeder Seite gemacht wird. Es läuft einmal in jede Richtung und dauert daher doppelt so lange.',
						'Füge optional ein **Tempo** und einen **Hinweis** hinzu – den Atem- oder Ausrichtungshinweis, der beim Mitmachen neben der Bewegung angezeigt wird.',
						'Prüfe die geschätzte Dauer, die der Editor für dich berechnet, und drücke dann **Speichern**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Beim Tippen werden Bewegungsnamen aus deinen früheren Plänen vorgeschlagen. Wählst du einen Vorschlag, bleibt dieselbe Haltung überall gleich geschrieben.',
				},
			],
		},
		{
			heading: 'An einen Kurs anhängen',
			blocks: [
				{
					type: 'list',
					items: [
						'Wähle beim Erstellen eines Kurses den Plan unter **Session-Plan**.',
						'Kurs schon erstellt? Auf der Kursseite drücken Organisatoren **An ein Kurs-Event anhängen** in der Karte **Session-Abfolge**.',
					],
				},
				{
					type: 'p',
					text: 'Teilnehmende sehen dann die ganze Abfolge auf der Kursseite. Ein privater Plan bleibt für alle anderen privat, aber die Teilnehmenden eines Kurses, an den du ihn hängst, können ihn sehen.',
				},
			],
		},
		{
			heading: 'Mitmachen',
			blocks: [
				{
					type: 'p',
					text: 'Öffne den Plan und drücke **Einheit starten**. Zeitgesteuerte Haltepositionen und Flows gehen von selbst weiter; bei Wiederholungen drückst du **Fertig**, wenn du fertig bist. Du kannst **Pausieren**, **Fortsetzen**, einen Schritt **Überspringen** oder **Abbrechen**. Wenn du fertig bist, wird die Einheit als Training in deinem Gym-Log gespeichert.',
				},
				{
					type: 'p',
					text: 'Die Handy-App spielt dieselbe Mitmach-Einheit ab, liest die Hinweise vor, hält den Bildschirm wach und läuft weiter, wenn du zu einer anderen App wechselst.',
				},
			],
		},
		{
			heading: 'Teilen',
			blocks: [
				{
					type: 'list',
					items: [
						'**Öffentlich machen** lässt alle den Plan finden und ihm folgen. **Link zum Teilen kopieren** macht den Plan öffentlich und kopiert einen Link, der auch ohne Anmeldung funktioniert.',
						'**In einem Club veröffentlichen**: Wähle den Club bei **Club auswählen…** und drücke **Veröffentlichen**. Er erscheint unter **Session-Vorlagen** im Tab **Vorlagen** des Clubs, und Mitglieder drücken **Übernehmen**, um ihre eigene Kopie zu bekommen.',
					],
				},
			],
		},
	],
	sources: {
		title: '2761214d4528b755',
		summary: '6ed93f306126bfd5',
		's0.heading': '75ab7687d1fdc4e6',
		's0.b0': '4c2393e2453c0847',
		's0.b1.i0': 'be6a427f8e3575ab',
		's0.b1.i1': '43033b89a725981f',
		's1.heading': 'd222e97495049181',
		's1.b0.i0': 'e1da2dcf855fd8cd',
		's1.b0.i1': '117837344c17aa7d',
		's1.b0.i2': '2e19d15f6adb30c7',
		's1.b0.i3': '4178a74d986586c6',
		's1.b0.i4': 'ba82220d774c7f84',
		's1.b0.i5': '03673097f36c78e9',
		's1.b0.i6': 'd02405ef4e9be33a',
		's1.b0.i7': '4f883b9f98fe5258',
		's1.b1': '63d86fc0ace9cb60',
		's2.heading': '27bf4831df1b4047',
		's2.b0.i0': '08f6e2680c9d0de7',
		's2.b0.i1': '91f068b693756ac2',
		's2.b1': '9021887b2281f1ca',
		's3.heading': '273869c12606c741',
		's3.b0': 'bfc8888c6226cf77',
		's3.b1': '4c67ea01c09f80f8',
		's4.heading': '692991f8b622c079',
		's4.b0.i0': '548fec5550dfaa6b',
		's4.b0.i1': '21ced8342dc5228c',
	},
};
