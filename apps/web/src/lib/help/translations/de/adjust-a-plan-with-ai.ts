import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'adjust-a-plan-with-ai',
	title: 'Einen Trainingsplan mit KI anpassen',
	summary: 'Beschreibe eine Änderung an deinem Plan in eigenen Worten, prüfe jeden vorgeschlagenen Eingriff und speichere erst, wenn du einverstanden bist.',
	sections: [
		{
			heading: 'Was es ändern kann',
			blocks: [
				{
					type: 'p',
					text: 'Mit KI anpassen macht aus einer Bitte wie *leg meinen langen Lauf auf Samstag* oder *mach nächste Woche leichter* Änderungen an einem gespeicherten Plan. Es kann ein Training auf einen anderen Tag derselben Woche verschieben, zwei Tage tauschen, eine Woche etwas hoch- oder herunterskalieren, eine Woche zur Erholungswoche machen oder ein Training auslassen.',
				},
				{
					type: 'p',
					text: 'Jede Änderung führen Threkirs eigene Planregeln aus. Die KI schreibt nie ein Training, eine Distanz oder eine Pace, daher bekommt eine Bitte wie *füge eine Bergeinheit hinzu* nur den Hinweis, dass das nicht geht. Für alles andere nutze **Plan bearbeiten**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Mit KI anpassen gibt es nur im Web, und es ist eventuell noch nicht eingeschaltet. Steht **Mit KI anpassen** nicht unter **Plan anpassen**, ist es für dich nicht verfügbar.',
				},
			],
		},
		{
			heading: 'Eine Änderung anfragen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne deinen Plan im Web und wähle **Plan anpassen**.',
						'Wähle **Mit KI anpassen**.',
						'Schreib, was geändert werden soll, und wähle dann **Änderungen vorschlagen**.',
						'Lies die **Vorgeschlagene Änderungen**: jedes Training, das verschoben, ausgelassen oder erleichtert wird, und jedes geänderte Wochenziel, jeweils vorher und nachher.',
						'Wähle **KI-Vorschläge übernehmen**, um sie zu speichern. Bis dahin hat sich an deinem Plan nichts geändert; wähle **Abbrechen**, um ihn so zu lassen.',
					],
				},
			],
		},
		{
			heading: 'Sicherheitsprüfungen vor dem Speichern',
			blocks: [
				{
					type: 'list',
					items: [
						'Änderungen, die eine Woche gemessen an deinem bisherigen Training in den Bereich mit hohem Verletzungsrisiko bringen würden, lassen sich nicht übernehmen. Die Seite nennt die Woche.',
						'Machen die Änderungen eine Woche härter, als dein bisheriges Training hergibt, oder legen sie zwei harte Einheiten auf aufeinanderfolgende Tage, wirst du **Härtere Änderungen übernehmen?** gefragt und musst **Trotzdem übernehmen** wählen.',
						'Ein Vorschlag, der sich nicht sicher umsetzen ließ, wird weggelassen, und die Seite sagt dir das.',
					],
				},
			],
		},
		{
			heading: 'Was dafür verwendet wird',
			blocks: [
				{
					type: 'list',
					items: [
						'Jede Anfrage verbraucht eine deiner täglichen KI-Coach-Nachrichten, dasselbe Kontingent wie beim Coach.',
						'Sie setzt den aktuellen KI-Hinweis voraus. Wirst du gebeten, ihn zu akzeptieren, wähle **In den Einstellungen ansehen** und akzeptiere ihn dort.',
						'An die KI gehen nur die anstehenden Trainings deines Plans und die Änderung, die du eingegeben hast.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Du kannst auch den Coach bitten, deinen Plan zu ändern. Er antwortet mit einem Link, der Mit KI anpassen mit deiner Bitte bereits ausgefüllt öffnet.',
				},
			],
		},
	],
	sources: {
		title: '3430390db6cef427',
		summary: '0b8f143261af9bcc',
		's0.heading': '44fa39d8b77c49be',
		's0.b0': '38fcc465ef1aec71',
		's0.b1': '7e6eec922334abd2',
		's0.b2': 'ca366aa955882170',
		's1.heading': 'f445fc4ffc97bebf',
		's1.b0.i0': '62be50b834eee366',
		's1.b0.i1': '490a29939b6ffad0',
		's1.b0.i2': '8dd005960648769c',
		's1.b0.i3': '6b71202d85d1ca61',
		's1.b0.i4': '1372a2a63c642a43',
		's2.heading': 'd9ef6a00bed5abfb',
		's2.b0.i0': '5b077f2018bffd38',
		's2.b0.i1': '2aae15cab49e816a',
		's2.b0.i2': 'aa84c731a647d1f3',
		's3.heading': '7e05806066a320c6',
		's3.b0.i0': '62c07e209d9ce339',
		's3.b0.i1': '1418c266b519f9d9',
		's3.b0.i2': '5de71e71f15f24a2',
		's3.b1': '12d00dbd647acb4c',
	},
};
