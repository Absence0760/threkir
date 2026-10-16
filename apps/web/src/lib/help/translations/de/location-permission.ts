import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'location-permission',
	title: 'Standortzugriff für die Laufaufzeichnung',
	summary: 'Welche Standortoption du unter Android und auf dem iPhone wählen solltest, was jede für deine Läufe bedeutet und wie du sie später in den Einstellungen änderst.',
	sections: [
		{
			heading: 'Warum die App nach deinem Standort fragt',
			blocks: [
				{
					type: 'p',
					text: 'Dein Standort zeichnet die Karte eines Laufs und misst Distanz und Pace. Ohne ihn zeichnet ein Lauf weiterhin Zeit und Schritte auf, aber keine Karte, Distanz oder Pace.',
				},
				{
					type: 'p',
					text: 'Du wirst bei der Einrichtung gefragt: Nach der Seite **Standortzugriff** öffnet ein Tippen auf **Berechtigung erteilen** die Abfrage deines Handys. Lehnst du ab, sagt dir die App das und bietet **Einstellungen öffnen** an. Hast du den Zugriff noch nicht erlaubt, wenn du auf **START** tippst, fragt dein Handy möglicherweise erneut.',
				},
			],
		},
		{
			heading: 'Unter Android',
			blocks: [
				{
					type: 'p',
					text: 'Androids erste Abfrage kann den Zugriff nur während der Nutzung der App erteilen. Damit der Lauf auch bei ausgeschaltetem Bildschirm erfasst wird, brauchst du **Immer zulassen**, und das lässt Android nur in den Einstellungen auswählen.',
				},
				{
					type: 'steps',
					items: [
						'Lass in der Abfrage **Genau** ausgewählt und tippe auf **Während der Nutzung der App**.',
						'Vor deinem ersten Lauf zeigt die App **Standort immer zulassen**. Tippe auf **Einstellungen öffnen**.',
						'Tippe unter **Berechtigungen** auf **Standort**, wähle **Immer zulassen** und kehre dann zur App zurück.',
					],
				},
				{
					type: 'p',
					text: 'Tippst du auf **Trotzdem starten**, zeichnet der Lauf ganz normal auf, solange die App im Vordergrund ist. Bei ausgeschaltetem Bildschirm oder in einer anderen App sendet Android deinen Standort möglicherweise nicht mehr: Die Uhr läuft weiter und nichts bereits Aufgezeichnetes geht verloren, aber die Distanz, die du in der Zeit zurücklegst, wird nicht gezählt. In dem Fall erscheint bei deiner Rückkehr eine Meldung, die mit **Die Aufzeichnung pausierte, während du weg warst** beginnt, mit einer Schaltfläche **Einstellungen**.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Der Hinweis vor einem Lauf erscheint einmal. Er kommt nur zurück, wenn du den Zugriff immer erlaubt hattest und dieser später entfernt wurde, zum Beispiel weil Android die Berechtigungen von Apps zurücksetzt, die du länger nicht geöffnet hast.',
				},
				{
					type: 'list',
					items: [
						'Mit **Ungefähr** ist der Standort zu grob, um einen Lauf zu messen: Du siehst den ganzen Lauf über **Ungefährer Standort — Distanz pausiert**.',
						'**Nur dieses Mal** gilt für den Lauf, den du gleich startest, und beim nächsten Mal wirst du erneut gefragt.',
						'Mit **Nicht zulassen** zeichnen Läufe nur Zeit und Schritte auf.',
					],
				},
			],
		},
		{
			heading: 'Auf dem iPhone',
			blocks: [
				{
					type: 'p',
					text: 'Auf dem iPhone reicht der Zugriff während der Nutzung der App: Ein Lauf zeichnet weiter auf, wenn der Bildschirm gesperrt ist oder du eine andere App verwendest. Die App fragt nie nach **Immer**, und du brauchst es nicht.',
				},
				{
					type: 'steps',
					items: [
						'Tippe in der Abfrage auf **Beim Verwenden der App erlauben**.',
						'Lass den genauen Standort in der Abfrage eingeschaltet. Ohne ihn ist deine Position zu grob, um die Distanz zu messen, und der Lauf zeigt **Ungefährer Standort — Distanz pausiert**.',
					],
				},
				{
					type: 'p',
					text: '**Einmal erlauben** gilt nur für diesen Lauf, und beim nächsten Mal wirst du erneut gefragt. Mit **Nicht erlauben** zeichnen Läufe nur Zeit und Schritte auf.',
				},
			],
		},
		{
			heading: 'Energiesparfunktionen',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Manche Android-Handys (Samsung, Xiaomi, OnePlus und andere) versetzen Apps in den Ruhezustand, um Akku zu sparen. Das kann die Aufzeichnung eines langen Laufs bei ausgeschaltetem Bildschirm stoppen, selbst mit **Immer zulassen**. Vor deinem ersten Lauf zeigt die App einmal **Aufzeichnung im Hintergrund aktiv halten**: Tippe auf **Einstellungen öffnen** und nimm Threkir von der Akkuoptimierung aus. Hast du auf **Nicht jetzt** getippt, öffne die Seite der App in den Einstellungen deines Handys, tippe auf **Akku** und wähle **Nicht eingeschränkt**. Die Bezeichnungen unterscheiden sich je nach Hersteller etwas.',
				},
			],
		},
		{
			heading: 'Später ändern',
			blocks: [
				{
					type: 'p',
					text: 'Unter Android:',
				},
				{
					type: 'steps',
					items: [
						'Öffne die **Einstellungen** deines Handys und tippe auf **Apps** und dann auf **Threkir**.',
						'Tippe auf **Berechtigungen** und dann auf **Standort**.',
						'Wähle **Immer zulassen** und schalte **Genauen Standort verwenden** ein.',
					],
				},
				{
					type: 'p',
					text: 'Auf dem iPhone:',
				},
				{
					type: 'steps',
					items: [
						'Öffne **Einstellungen** › **Datenschutz & Sicherheit** › **Ortungsdienste** und prüfe, ob die **Ortungsdienste** eingeschaltet sind.',
						'Tippe auf **Threkir** und wähle **Beim Verwenden der App**.',
						'Schalte **Genauer Standort** ein.',
					],
				},
				{
					type: 'p',
					text: 'Ist der Standort beim Start eines Laufs aus oder blockiert, weist der Laufbildschirm darauf hin, und seine Schaltfläche **Einstellungen** bringt dich an die richtige Stelle.',
				},
			],
		},
		{
			heading: 'Was die App mit deinem Standort macht',
			blocks: [
				{
					type: 'list',
					items: [
						'Sie liest deinen Standort, während du einen Lauf aufzeichnest und wenn sich eine Karte auf dich zentriert, etwa wenn du eine Route erstellst oder eine Datenschutzzone setzt. Zwischen den Läufen verfolgt sie dich nicht.',
						'Unter Android zeigt eine Benachrichtigung an, dass ein Lauf aufgezeichnet wird, sofern du Benachrichtigungen erlaubst.',
						'Der Track eines Laufs bleibt auf deinem Handy, bis er mit deinem Konto synchronisiert wird oder du ihn teilst, und wer ihn sehen kann, richtet sich nach deinen Datenschutzeinstellungen: siehe [[guide:your-data-and-privacy|deine Daten und Datenschutz]].',
						'Um zu verbergen, wo du wohnst, richte [[guide:privacy-zones|Datenschutzzonen]] ein. Deine Live-Position wird nur geteilt, wenn du [[guide:live-tracking-and-safety|Live-Tracking]] einschaltest.',
					],
				},
			],
		},
	],
	sources: {
		'title': '583816a170012c19',
		'summary': '56769a6e224ff156',
		's0.heading': '794b04c19c7668d8',
		's0.b0': 'af2524b060ff7e41',
		's0.b1': 'c4efda4e34e087e7',
		's1.heading': 'd085d4c0606e9a65',
		's1.b0': 'f87947ee024ca95d',
		's1.b1.i0': '74eca884f8eb053b',
		's1.b1.i1': 'bc08250477141230',
		's1.b1.i2': 'cd926bc8428f270d',
		's1.b2': '3f9237c89f00534f',
		's1.b3': '6c15e5f41c0dbad5',
		's1.b4.i0': '9c6c79a701984fae',
		's1.b4.i1': 'd35c46ecb6f1579e',
		's1.b4.i2': '09d7ce333fe83b8c',
		's2.heading': '873081b6807b4197',
		's2.b0': '6912b4c52f4c4037',
		's2.b1.i0': '302121c948975146',
		's2.b1.i1': '5776de36117755b3',
		's2.b2': 'dd5515e417bcce18',
		's3.heading': 'd91eca07ad12c491',
		's3.b0': '5ecc6e3ad1cacf65',
		's4.heading': '8489bd921c93cd06',
		's4.b0': '8a324e6ccca0ee87',
		's4.b1.i0': '682f9bd3caa2bb73',
		's4.b1.i1': '8cad8da0c6d30e3e',
		's4.b1.i2': '007cea366706e1e4',
		's4.b2': '1eb507e8f5d10b2b',
		's4.b3.i0': '29ad09bb32235340',
		's4.b3.i1': '54f8b50ec24d5250',
		's4.b3.i2': '4bbab96422f563b9',
		's4.b4': '20e869463ad7c51c',
		's5.heading': '11a805eb39c14582',
		's5.b0.i0': 'e4acbdfc462c84a6',
		's5.b0.i1': '1a49253f9adf5652',
		's5.b0.i2': '79d0adcf35c722c0',
		's5.b0.i3': 'f79c6d8e7f96a30f',
	},
};
