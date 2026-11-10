import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'how-segment-times-are-measured',
	title: 'Wie Segmentzeiten gemessen werden',
	summary: 'Zeiten auf Segmenten und Parkstrecken laufen von einer Startlinie bis zu einer Endlinie, jeweils in der richtigen Richtung überquert, und dein schnellster Durchgang zählt.',
	sections: [
		{
			heading: 'Start- und Endlinien',
			blocks: [
				{
					type: 'p',
					text: 'Jedes Segment hat eine Startlinie und eine Endlinie, je eine an jedem Ende quer über den Weg, in Richtung des Segments ausgerichtet und 15 m zu jeder Seite reichend. Eine Parkstrecke ist ebenfalls ein Segment und wird deshalb genauso gemessen.',
				},
				{
					type: 'list',
					items: [
						'Deine Zeit läuft von dem Moment, in dem dein Lauf die Startlinie überquert, bis zu dem Moment, in dem er die Endlinie überquert.',
						'Jede Überquerung wird zwischen den beiden GPS-Punkten zu beiden Seiten der Linie berechnet, statt einfach den Punkt zu nehmen, der zufällig am nächsten lag, sodass die Zeit näher an der echten liegt.',
						'Beide Linien müssen in Richtung des Segments überquert werden. Eine rückwärts überquerte Linie zählt nicht.',
						'Die Distanz, die du zwischen den beiden Überquerungen zurückgelegt hast, darf höchstens 25 % von der Länge des Segments abweichen, und auf einer Parkstrecke musst du dazwischen jeden Kontrollpunkt in der richtigen Reihenfolge passieren.',
					],
				},
			],
		},
		{
			heading: 'Warum ein Weg daneben nicht zählt',
			blocks: [
				{
					type: 'p',
					text: 'Ein Lauf auf einem Weg, der 20 m entfernt neben dem Segment verläuft, kommt beiden Enden nahe, ohne je durch die Linien zu laufen, und bekommt daher keine Zeit. Ebenso wenig der Hinweg einer Hin-und-zurück-Route, die nur nahe am Ende vorbeiführt.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Starte die Aufzeichnung kurz vor der Startlinie. Ein Lauf, dessen Aufzeichnung auf der Linie oder dahinter beginnt, überquert sie nie und bekommt auf diesem Segment keine Zeit.',
				},
			],
		},
		{
			heading: 'Mehr als ein Durchgang',
			blocks: [
				{
					type: 'list',
					items: [
						'Führt dein Lauf mehr als einmal über das Segment, zählt dein schnellster Durchgang.',
						'Ein Aufwärmen, das zurück über die Startlinie führt, verlängert deine Zeit nicht: Die Zeit beginnt mit deiner letzten Überquerung der Startlinie vor dem Ende.',
						'Bei einem Rundkurs, dessen Start und Ende dieselbe Linie sind, kann die Überquerung, die eine Runde beendet, nicht zugleich die nächste starten. Deshalb wird nur jede zweite Runde gemessen (die erste, die dritte und so weiter), und die schnellste davon zählt. Ein Rundkurs mit getrennter Start- und Endlinie misst jede Runde.',
					],
				},
			],
		},
		{
			heading: 'Segmente ohne Linien',
			blocks: [
				{
					type: 'p',
					text: 'Ein Segment, das an einem Ende zu kurz ist, um dort eine Linie zu setzen, hat keine Linien. Es wird weiterhin auf die alte Art gemessen: Dein Lauf muss zuerst bis auf 35 m an seinen Start und dann bis auf 35 m an sein Ende herankommen.',
				},
			],
		},
		{
			heading: 'Ältere Versuche',
			blocks: [
				{
					type: 'p',
					text: 'Versuche, die aufgezeichnet wurden, bevor Segmente Linien hatten, wurden auf die alte Art gemessen, durch Vorbeilaufen nahe Start und Ende. Jeder wird mit den Linien neu gemessen, sobald die Person den Lauf das nächste Mal auf der Website öffnet. Dabei kann sich seine Zeit ändern, und er kann verschwinden, wenn der Lauf die Linien nie überquert hat.',
				},
				{
					type: 'p',
					text: 'Bis jeder Versuch auf einem Segment neu gemessen wurde, weist seine Bestenliste darauf hin, dass einige ältere Versuche auf die alte Art gemessen wurden.',
				},
			],
		},
	],
	sources: {
		title: 'af6ac26d6646f774',
		summary: 'a18775a50f19720a',
		's0.heading': 'e4b2458df12fdaf3',
		's0.b0': 'cd68d1e94a0f5ab9',
		's0.b1.i0': '6f3bd850e275ed2a',
		's0.b1.i1': '1f53338704ded34d',
		's0.b1.i2': 'bbbd3c6ebb557922',
		's0.b1.i3': '6b8289f9cfe75cdc',
		's1.heading': 'a7fcd26c4192d17b',
		's1.b0': '433e0989f5c0bcdb',
		's1.b1': '762d24e1e2186155',
		's2.heading': '07aa1107fe80687c',
		's2.b0.i0': 'd1cc20d8bffef410',
		's2.b0.i1': '49b20e543d91d563',
		's2.b0.i2': 'd8dc1f1202af2dc9',
		's3.heading': '6ce1d76024b4fe1f',
		's3.b0': '2f8dce267fbf234c',
		's4.heading': 'f2e748afe43f1604',
		's4.b0': '73985bbd2197a3b7',
		's4.b1': '02549166218656ab',
	},
};
