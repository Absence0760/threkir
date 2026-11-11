import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-results-explained',
	title: 'Rennergebnisse erklärt',
	summary: 'Was Brutto- und Nettozeit bedeuten, wie Platzierungen ermittelt werden, was die Kennzeichnungen Manuell, Veranstalter, DNF, DNS und ausstehend aussagen und wie du aus deinem Track neu misst.',
	sections: [
		{
			heading: 'Bruttozeit und Nettozeit',
			blocks: [
				{
					type: 'list',
					items: [
						'**Bruttozeit** wird von dem Moment, in dem der Veranstalter GO gegeben hat, bis zu dem Moment gemessen, in dem du das Ziel überquert hast. GO wird von unserem Server gestempelt, daher haben alle im Rennen denselben Start.',
						'**Nettozeit** wird von dem Moment, in dem du die Startlinie der Strecke überquert hast, bis zu deinem Zieleinlauf gemessen. Hat dein Handy oder deine Uhr kein Überqueren der Startlinie erkannt, läuft sie ab dem Moment, in dem du auf deinem eigenen Gerät auf Start gedrückt hast, einschließlich aller Pausen.',
						'Ein selbstgestopptes Rennen hat keinen GO und daher keine Bruttozeit: Seine Liste zeigt deine Nettozeit, von der Startlinie bis zur Ziellinie.',
						'Die große Zeit in der Liste ist deine Bruttozeit, wenn es im Rennen einen GO gab, sonst deine Nettozeit. Die Platzierungen werden aus dieser großen Zeit ermittelt.',
					],
				},
				{
					type: 'p',
					text: 'Im Web lautet die kleinere Zeile unter einer Zeit etwa „Brutto 41:58 · Netto 41:20“. In der Handy-App wird unter der Hauptzeit eine „Netto“-Zeit angezeigt, wenn sie davon abweicht. Bist du verspätet gestartet, ist deine Bruttozeit länger als deine Nettozeit.',
				},
			],
		},
		{
			heading: 'Platzierungen gelten pro Strecke',
			blocks: [
				{
					type: 'p',
					text: 'Hat ein Rennen mehr als eine Strecke, hat jede Strecke ihre eigene Liste und ihre eigenen Platzierungen. Wer über 5K ins Ziel kommt, wird nie mit jemandem von der 10K verglichen. Ergebnisse ohne Strecke werden zusammengefasst (**Keine Strecke** auf der Event-Seite, **Sonstige** auf der Live-Seite).',
				},
				{
					type: 'p',
					text: 'Nur wer ins Ziel kommt, erhält eine Platzierung. Bei Gleichstand entscheidet, wessen Ergebnis zuerst eingetroffen ist.',
				},
			],
		},
		{
			heading: 'Wie der Zieleinlauf erfasst wurde',
			blocks: [
				{
					type: 'list',
					items: [
						'**Kein Abzeichen**: Das Handy oder die Uhr der teilnehmenden Person hat den Zieleinlauf gestoppt, in dem Moment, in dem sie die Ziellinie überquert hat, oder am 30-m-Kreis um das Ziel bei einer Strecke ohne Ziellinie. Das ist der Normalfall, daher kennzeichnen ihn weder das Web noch die Handy-App.',
						'**Manuell**: Die teilnehmende Person hat das Rennen von Hand beendet, entweder mit **Rennen beenden** nach mindestens 90 % der Strecke oder während des Rennens mit **Meine Zeit einreichen** im Web.',
						'**Veranstalter** (im Web **Vom Veranstalter bearbeitet**): Der Veranstalter hat dieses Ergebnis eingetragen oder korrigiert, oder die teilnehmende Person wurde als DNF markiert, als der Veranstalter das Rennen beendet hat.',
					],
				},
			],
		},
		{
			heading: 'DNF und DNS',
			blocks: [
				{
					type: 'list',
					items: [
						'**DNF** (did not finish, nicht ins Ziel gekommen): Die teilnehmende Person ist gestartet, aber nicht ins Ziel gekommen. Das passiert, wenn jemand vor 90 % der Strecke **Als DNF beenden** wählt, wenn der Veranstalter das Rennen beendet, während jemand noch unterwegs ist, oder wenn der Veranstalter es einträgt.',
						'**DNS** (did not start, nicht gestartet): von der teilnehmenden Person mit **DNS eintragen** oder vom Veranstalter erfasst.',
						'Beide erhalten keine Platzierung. Auf der Live-Seite stehen sie unter **Nicht beendet**.',
					],
				},
			],
		},
		{
			heading: 'Ausstehende Ergebnisse',
			blocks: [
				{
					type: 'p',
					text: 'Hat der Veranstalter die automatische Genehmigung ausgeschaltet, wartet jedes neue Ergebnis auf ihn. Auf der Event-Seite im Web zeigt es **AUSSTEHEND** und noch keinen Platz; in der Handy-App und auf der Live-Seite zeigt es **Ausstehend**. Sobald der Veranstalter **Genehmigen** wählt, nimmt es seinen Platz in der Liste ein.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Ein **Zertifikat** für den Zieleinlauf kann erst heruntergeladen werden, wenn ein Ergebnis mit Zieleinlauf genehmigt wurde.',
				},
			],
		},
		{
			heading: 'Aus deinem Track neu messen',
			blocks: [
				{
					type: 'p',
					text: 'Hat dein Handy eine Linie verpasst, ist dein Ergebnis ein unerwartetes DNF oder bist du mit einer Apple Watch gelaufen, kannst du dein Ergebnis aus dem aufgezeichneten Lauf neu messen. Öffne den Lauf im Web: Gehört er zu einem Rennen, zeigt er **Aus meinem Track neu messen** mit deinem aktuellen Ergebnis neben dem, das dein Track ergibt.',
				},
				{
					type: 'steps',
					items: [
						'Prüfe die beiden Spalten: Bruttozeit, Nettozeit und ob Start und Ziel über die Linie gestoppt wurden.',
						'Wähle **Ergebnis neu messen** und dann **Ergebnis ersetzen**.',
					],
				},
				{
					type: 'list',
					items: [
						'Dein Track wird anhand der Start- und Ziellinie gemessen, mit denen das Rennen ausgetragen wurde, und mit derselben Uhrzeit, die dein Handy oder deine Uhr während des Rennens verwendet hat.',
						'Neu messen kannst du bis 24 Stunden nach dem Ende des Rennens. Danach kann nur noch der Veranstalter eine Zeit ändern.',
						'Eine Neumessung ersetzt ein DNF, eine von Hand beendete Zeit und ein Ergebnis, das auf Prüfung wartet. Sie ersetzt nie eine Zeit, die der Veranstalter festgelegt hat, oder ein Ergebnis, das bereits über beide Linien gestoppt wurde; in einem selbstgestoppten Rennen ersetzt nur ein schnellerer, über beide Linien gestoppter Versuch ein solches Ergebnis.',
						'Genehmigt der Veranstalter Ergebnisse von Hand, geht ein neu gemessenes Ergebnis zur Genehmigung an ihn zurück.',
					],
				},
			],
		},
		{
			heading: 'Etwas sieht falsch aus',
			blocks: [
				{
					type: 'list',
					items: [
						'Gar kein Ergebnis? Hatte dein Gerät im Ziel kein Signal, sendet es das Ergebnis, sobald es wieder verbunden ist, innerhalb von 24 Stunden nach Rennende. Innerhalb derselben 24 Stunden kannst du es auch aus deinem Track neu messen.',
						'Ein DNF, das du für falsch hältst, oder eine Zeit, die nicht stimmt? Frag den Veranstalter. Er kann es im Web korrigieren, und das Ergebnis trägt dann die Veranstalter-Kennzeichnung.',
					],
				},
				{
					type: 'p',
					text: 'Zur Sicht der Teilnehmenden siehe [[guide:racing-in-a-race|Bei einem Live-Rennen mitlaufen]]. Für Veranstalter: [[guide:race-day-for-hosts|Renntag für Veranstalter]].',
				},
			],
		},
	],
	sources: {
		title: 'c5d9f999ac691293',
		summary: '184c2d298bd26fe6',
		's0.heading': 'c64bc4e8176b0753',
		's0.b0.i0': '5c206fcfa0703269',
		's0.b0.i1': 'cb9512f304721331',
		's0.b0.i2': 'd7cbf99a35b6a2ef',
		's0.b0.i3': 'cf4e236435fc2502',
		's0.b1': 'a18a5324618c6db1',
		's1.heading': '280c1a73657807c5',
		's1.b0': '86d271497a41304f',
		's1.b1': '692dd04c06057463',
		's2.heading': '6e3b7d9c6cfced31',
		's2.b0.i0': '35a51ea02054bef1',
		's2.b0.i1': '53388c67a2b02b1b',
		's2.b0.i2': '811f16eecd7e7ab7',
		's3.heading': '6a340a4c16d7e613',
		's3.b0.i0': '6f69c4d43a38c323',
		's3.b0.i1': '3604d88945607e72',
		's3.b0.i2': 'f045b1b42c362f65',
		's4.heading': '5ed96724cf8a0430',
		's4.b0': 'f02bc0251822ab1e',
		's4.b1': 'a9bb4df966953e7a',
		's5.heading': '58d90ac423027da2',
		's5.b0': '8fe61e9de9317b69',
		's5.b1.i0': 'd6fc360bf0506c2c',
		's5.b1.i1': 'b0eb18e5a8270886',
		's5.b2.i0': '7b1ea13025902315',
		's5.b2.i1': '7e44288e6edf8a96',
		's5.b2.i2': '8a9c94b45aba53b2',
		's5.b2.i3': '84812a40e9aafb58',
		's6.heading': 'badeb43244f6c195',
		's6.b0.i0': '9afe7b467f14e81b',
		's6.b0.i1': 'b8f3e2e296b07673',
		's6.b1': '9f40f68ca81e692f',
	},
};
