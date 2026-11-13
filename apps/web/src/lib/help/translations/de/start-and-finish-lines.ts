import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'start-and-finish-lines',
	title: 'Start- und Ziellinien',
	summary: 'Was die Start- und Ziellinien einer Strecke sind, wie sie für dich gesetzt werden und wie du sie selbst verschiebst, drehst, verbreiterst oder setzt.',
	sections: [
		{
			heading: 'Was eine Linie ist',
			blocks: [
				{
					type: 'p',
					text: 'Jede Strecke eines Rennens hat eine Startlinie und eine Ziellinie. Eine Linie liegt an einer Stelle quer über der Strecke, zeigt in die Laufrichtung und reicht zu jeder Seite eine festgelegte Weite. Überquert wird sie nur, wenn man in dieser Richtung und innerhalb ihrer Breite durch sie hindurchläuft.',
				},
				{
					type: 'p',
					text: 'Das ist der Unterschied zu einem Zielpunkt mit einem Kreis von 30 m darum. Ein Kreis zählt alle, die in die Nähe kommen: jemanden auf einem Weg, der daneben verläuft, oder auf dem Hinweg einer Hin-und-zurück-Strecke, die auf demselben Weg zurückkommt. Eine Linie zählt sie nicht, denn sie laufen nie in der richtigen Richtung durch sie hindurch.',
				},
			],
		},
		{
			heading: 'Für dich gesetzte Linien',
			blocks: [
				{
					type: 'p',
					text: 'Hat eine Strecke eine Route, bekommt sie beide Linien von ihr. Die Startlinie liegt auf dem ersten Punkt der Route und zeigt entlang der Route. Die Ziellinie liegt auf ihrem letzten Punkt und zeigt in die Richtung, in der die Route dort ankommt. Jede reicht 15 m zu jeder Seite. Sie folgen der Route: Änderst du die Route, wandern sie mit.',
				},
				{
					type: 'p',
					text: 'Linien erscheinen, sobald das Event mit mindestens einer Strecke gespeichert ist. Öffne das Event, wähle **Event bearbeiten** und suche **Start- und Ziellinien**. Jede Strecke hat eine Karte und eine Zeile pro Linie, die angibt, woher die Linie stammt: **Aus der Route**, **Von einem Organisator gesetzt** oder **Keine**.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Hat die Person, der die Route gehört, eine Datenschutzzone über dem Start oder dem Ende der Route, ist dieses Ende für alle anderen verborgen und bekommt daher keine Linie. Setze diese Linie selbst.',
				},
			],
		},
		{
			heading: 'Eine Linie verschieben, drehen oder verbreitern',
			blocks: [
				{
					type: 'steps',
					items: [
						'Wähle neben **Startlinie** oder **Ziellinie** die Option **Bearbeiten**.',
						'Zieh auf der Karte die Mitte der Linie, um sie zu verschieben, und ihren Griff, um sie zu drehen. Ist die Karte aus, wähle **Karte laden**, oder verzichte auf die Karte und gib die Werte stattdessen ein.',
						'Oder gib **Breitengrad**, **Längengrad** und **Richtung (Grad)** ein. Die Richtung ist die, in der Läufer die Linie überqueren, im Uhrzeigersinn ab Norden: 0 ist Norden, 90 Osten, 180 Süden und 270 Westen.',
						'Stell **Breite je Seite** auf einen Wert von 5 bis 100 m ein. Mach sie breit genug, um die ganze Straße oder den ganzen Weg abzudecken, und noch etwas mehr.',
						'Wähle **Linie speichern**.',
					],
				},
				{
					type: 'p',
					text: 'Jede Linie wird für sich und sofort gespeichert; du musst das Event nicht speichern. Eine Linie, die du verschoben hast, zeigt **Von einem Organisator gesetzt**. Mit **Auf Route zurücksetzen** legst du sie wieder dorthin, wo die Route sie platziert.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Eine Linie, die du gesetzt hast, bleibt genau dort, wo du sie hingelegt hast, auch wenn du später die Route der Strecke änderst. Prüfe nach einer Routenänderung die Warnungen unter jeder Linie.',
				},
			],
		},
		{
			heading: 'Warnungen im Editor',
			blocks: [
				{
					type: 'list',
					items: [
						'Die Linie ist mehr als 100 m von der Route der Strecke entfernt. Prüfe, ob sie richtig sitzt.',
						'Die Linie zeigt gegen die Richtung der Route, Läufer auf der Route würden sie also rückwärts überqueren. Dreh sie um.',
						'Die Route überquert ihre eigene Ziellinie vor dem Ende, wie bei einer Rundenstrecke oder einer Bahn. Der Zieleinlauf über die Linie ist dann für diese Strecke ausgeschaltet, und Läufer beenden mit Stopp oder Ziel.',
					],
				},
			],
		},
		{
			heading: 'Strecken ohne Route',
			blocks: [
				{
					type: 'p',
					text: 'Eine Strecke ohne Route hat keine Linien, bis du sie setzt. Wähle **Startlinie setzen** oder **Ziellinie setzen**. Hast du die Karte vorher an die Stelle bewegt, wird die Linie zunächst in die Mitte der Karte gesetzt; andernfalls gib ihre Position ein. Lege dann ihre Richtung und Breite fest und wähle **Linie speichern**. **Linie entfernen** nimmt eine Linie, die du gesetzt hast, wieder weg.',
				},
			],
		},
		{
			heading: 'Linien werden beim Rennstart eingefroren',
			blocks: [
				{
					type: 'p',
					text: 'Wenn du ein Rennen scharf schaltest (bei einem selbstgestoppten Rennen, wenn sein Zeitraum öffnet), werden die Linien jeder Strecke für dieses Rennen kopiert. Alle Teilnehmenden überqueren dann dieselben Linien, egal was sich während des Rennens ändert. Eine spätere Änderung gilt ab dem nächsten Rennen. Die Event-Seite und die Live-Rennseite zeigen die Linien, mit denen das Rennen scharf geschaltet wurde.',
				},
			],
		},
		{
			heading: 'Prüfungen vor einem Rennen',
			blocks: [
				{
					type: 'p',
					text: 'Bevor ein Rennen scharf geschaltet wird, werden die Linien jeder Strecke geprüft, im Web und in der Handy-App. Bei einer Warnung kannst du **Trotzdem scharf schalten**; ein mit **Muss behoben werden:** markiertes Problem verhindert das Scharfschalten, bis du es im Event-Editor im Web behebst.',
				},
				{
					type: 'list',
					items: [
						'Eine Strecke ohne Ziellinie und ohne Zielpunkt: eine Warnung, weil ihre Teilnehmenden von Hand beenden. Bei einem selbstgestoppten Rennen muss das behoben werden.',
						'Eine Strecke ohne Startlinie: Bei einem selbstgestoppten Rennen muss das behoben werden. Andere Rennen können ohne sie starten.',
						'Eine Route, die ihre eigene Ziellinie vor dem Ende überquert: eine Warnung, weil der Zieleinlauf über die Linie für diese Strecke aus ist. Bei einem selbstgestoppten Rennen muss das behoben werden.',
						'Eine Linie, die mehr als 100 m von der Route entfernt ist: eine Warnung bei jeder Art von Rennen.',
					],
				},
				{
					type: 'p',
					text: 'Welche Art von Rennen du durchführst, legst du unter **Wie das Rennen startet** fest; siehe [[guide:choose-how-your-race-starts|Festlegen, wie dein Rennen startet]].',
				},
			],
		},
	],
	sources: {
		title: 'e32b975b30a0bfdf',
		summary: '007484d24c448df5',
		's0.heading': 'b2178bb9e4c07f85',
		's0.b0': '7b22e9bee9ea6e44',
		's0.b1': 'e18c2ba36732dafb',
		's1.heading': '6ae01aac1742fa11',
		's1.b0': '98879a39846cccd2',
		's1.b1': '1121c7b877f6a658',
		's1.b2': '5d09b8607f6a2f22',
		's2.heading': 'b839a49fc88eb9bb',
		's2.b0.i0': 'f9a4dd08d366b730',
		's2.b0.i1': '0bfc28ecb00a6d5b',
		's2.b0.i2': '29eaf88dee6df1d8',
		's2.b0.i3': '082f59f63580a00b',
		's2.b0.i4': '008936c6ea875617',
		's2.b1': 'e6292e6047487d65',
		's2.b2': '5bad76f945b81e03',
		's3.heading': '49bbc9db5d4c7163',
		's3.b0.i0': 'c519f8cea9bd87d0',
		's3.b0.i1': 'e08a656a24f1ed58',
		's3.b0.i2': 'aa848004795cf7a1',
		's4.heading': '3bd16f8003e613ef',
		's4.b0': 'adfbcab88a7c3e90',
		's5.heading': 'be581f997710aa1d',
		's5.b0': 'b691f01dae47a921',
		's6.heading': 'a1cbd797f4858538',
		's6.b0': '3ab85eab34b17f4c',
		's6.b1.i0': 'e5b89e5070aad84a',
		's6.b1.i1': '2d67c55e24d207a9',
		's6.b1.i2': '1ecbd8a36af71c78',
		's6.b1.i3': '84f19ca583307307',
		's6.b2': 'cfbf64534e49a993',
	},
};
