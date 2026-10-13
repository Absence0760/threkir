import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-results-explained',
	source: '41529f989e7110e2',
	title: 'Rennergebnisse erklärt',
	summary: 'Was Brutto- und Netto-Zeit bedeuten, wie Platzierungen pro Strecke ermittelt werden und was die Kennzeichnungen Manuell, Veranstalter, DNF, DNS und ausstehend aussagen.',
	sections: [
		{
			heading: 'Brutto-Zeit und Netto-Zeit',
			blocks: [
				{
					type: 'list',
					items: [
						'**Brutto-Zeit** wird von dem Moment, in dem der Veranstalter LOS gegeben hat, bis zu dem Moment gemessen, in dem du das Ziel überquert hast. LOS wird von unserem Server gestempelt, daher haben alle im Rennen denselben Start.',
						'**Netto-Zeit** wird von dem Moment, in dem du auf deinem eigenen Gerät auf Start gedrückt hast, bis zu deinem Zieleinlauf gemessen, einschließlich aller Pausen.',
						'Die große Zeit in der Liste ist deine Brutto-Zeit, wenn es im Rennen ein LOS gab, sonst deine Netto-Zeit. Die Platzierungen werden aus dieser großen Zeit ermittelt.',
					],
				},
				{
					type: 'p',
					text: 'Im Web lautet die kleinere Zeile unter einer Zeit etwa „Brutto 41:58 · Netto 41:20“. In der Handy-App wird unter der Hauptzeit eine „Netto“-Zeit angezeigt, wenn sie davon abweicht. Bist du verspätet gestartet, ist deine Brutto-Zeit länger als deine Netto-Zeit.',
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
						'**Kein Abzeichen**: Das Handy oder die Uhr der teilnehmenden Person hat die Ziellinie erkannt. Das ist der Normalfall, daher kennzeichnen ihn weder das Web noch die Handy-App.',
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
			heading: 'Etwas sieht falsch aus',
			blocks: [
				{
					type: 'list',
					items: [
						'Gar kein Ergebnis? Hatte dein Gerät im Ziel kein Signal, sendet es das Ergebnis, sobald es wieder verbunden ist, innerhalb von 24 Stunden nach Rennende.',
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
};
