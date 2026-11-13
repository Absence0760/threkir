import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'park-courses',
	title: "Parkstrecken: Kontrollpunkte, Saisons, Monate und Bestenlisten",
	summary: "Wie eine Parkstrecke deinen Lauf misst, warum jeder Kontrollpunkt zählt, wann eine Saison und ein Monat beginnen und wie die Listen Schnellste und Meiste Läufe die Rangfolge bilden.",
	sections: [
		{
			heading: "Was eine Parkstrecke ist",
			blocks: [
				{ type: 'p', text: "Eine Parkstrecke ist eine feste Zeitlaufstrecke auf einem Weg in einem State Park oder Nationalpark. Es gibt keinen Veranstalter und keinen Wettkampftag: Lauf sie, wann immer der Park geöffnet ist, und ein Lauf, der die ganze Strecke abdeckt, bekommt eine Zeit. Du findest sie unter **Jederzeit laufen** auf [[route:/races|Rennen & Strecken]], die nächstgelegenen zuerst, sobald du einen Ort festlegst, oder alle unter [[route:/parks|Parkstrecken]]. Wähle oben auf der Seite Rennen & Strecken **Strecken**, um alle Strecken für sich zu sehen, ohne den Rennkalender." },
				{
					type: 'list',
					items: [
						"Es ist ein Zeitlauf, kein Rennen. Der Weg bleibt für alle offen und niemand sichert ihn ab, also halte dich an die Regeln des Parks und lass anderen auf dem Weg den Vortritt.",
						"Jede Streckenseite zeigt Distanz, Anstieg, Form, Untergrund und Schwierigkeit, woher die Streckenlinie stammt und ob die Strecke geöffnet ist.",
						"Wähle **Diese Strecke navigieren**, um der Strecke als Route zu folgen. Solange die Strecke gesperrt ist, wird das nicht angeboten.",
						"Die **Streckenbeschreibung** auf der Streckenseite nennt, wo du parkst, und jede Abzweigung der Reihe nach mit Wegnamen, dazu Brücken, Furten, Wechsel des Untergrunds und Anstiege. Sie ist aus Kartendaten erstellt; solange niemand sie im Park abgelaufen ist, steht das über der Liste. Dieselbe Beschreibung steht in der GPX-Datei der Strecke.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Eine gesperrte Strecke nimmt keine neuen Zeiten an: Ein Lauf darüber, solange sie gesperrt ist, wird nicht gemessen, und die Zeiten, die sie schon hat, bleiben auf ihren Listen. Lauf sie bitte nicht, bis sie wieder geöffnet ist. Die Seite zeigt, wann ihr Status zuletzt geprüft wurde." },
			],
		},
		{
			heading: "Kontrollpunkte: Warum Abkürzungen nie zählen",
			blocks: [
				{ type: 'p', text: "Neben Start und Ziel kann eine Strecke unterwegs Kontrollpunkte haben. Dein Lauf bekommt nur dann eine Zeit, wenn er jeden Kontrollpunkt in der richtigen Reihenfolge zwischen Start und Ziel passiert. Ein Lauf, der eine Ecke abschneidet, eine Serpentine auslässt oder einen Pfad quer durch die Mitte nimmt, verpasst einen Kontrollpunkt und bekommt keine Zeit." },
				{ type: 'p', text: "Bleib auf dem markierten Weg. Abkürzungen beschädigen den Weg, und Parks werten sie als Verstoß gegen ihre Regeln." },
			],
		},
		{
			heading: "Saisons folgen der Uhr des Parks",
			blocks: [
				{ type: 'p', text: "Eine Saison ist ein Kalenderjahr in der Zeitzone des Parks, nicht in deiner. Die Listen beginnen um Mitternacht am 1. Januar neu, dort wo der Park liegt." },
				{ type: 'p', text: "Ein Lauf, der zum Beispiel um 22:00 Uhr am 31. Dezember in einem Park in Virginia startet, zählt für dieses Jahr, auch wenn dein Handy auf eine Zeitzone eingestellt ist, in der schon der 1. Januar ist." },
			],
		},
		{
			heading: "Die Liste Schnellste",
			blocks: [
				{
					type: 'list',
					items: [
						"**Schnellste** ordnet jede Person nach ihrer besten Zeit auf der Strecke. Du erscheinst einmal, mit deinem besten Lauf.",
						"Standardmäßig zeigt sie dieses Jahr. Wähle **Dieser Monat** für den bisherigen Monat oder **Gesamt** für die besten Zeiten aller Zeiten.",
						"Filtere nach Geschlecht oder Altersklasse. Der Altersfilter enthält nur Personen, die dem Teilen von Gesundheitsdaten zugestimmt haben, daher kann er kürzer sein als die ganze Liste.",
					],
				},
			],
		},
		{
			heading: "Die Liste Meiste Läufe",
			blocks: [
				{ type: 'p', text: "**Meiste Läufe** belohnt die Stammgäste. Sie zählt die Tage, an denen du die Strecke absolviert hast, in der Zeitzone des Parks, also zählen mehrere Runden an einem Tag als einer." },
			],
		},
		{
			heading: "Monate: jeden Monat eine neue Liste",
			blocks: [
				{ type: 'p', text: "Beide Listen gibt es auch Monat für Monat. Ein Monat ist ein Kalendermonat in der Zeitzone des Parks, von Mitternacht am 1. bis Mitternacht am 1. des nächsten Monats. Ein Lauf um 23:30 Uhr am 31. Oktober dort, wo der Park liegt, zählt also für Oktober." },
				{
					type: 'list',
					items: [
						"Wähle **Dieser Monat**, um den bisherigen Monat zu sehen, und blättere mit den Pfeilen neben dem Monatsnamen zu früheren Monaten zurück.",
						"Jede Strecke auf der Seite eines Parks zeigt, wie viele Personen sie diesen Monat gelaufen sind.",
						"Eine Parkstrecken-Zeit auf der Seite deines Laufs zeigt ihren Platz in diesem Monat und in diesem Jahr, etwa Platz 2 im November, Platz 9 im Jahr 2026. Der Sticker **Parkstrecke** auf einem geteilten Bild zeigt den Platz im Monat und auch den Platz im Jahr, wenn er unter den ersten 10 ist.",
						"Wenn dort, wo der Park liegt, ein Monat endet, bekommst du im Posteingang eine Nachricht mit deiner Bestzeit aus dem Monat auf jeder Strecke, die du gelaufen bist. Schalte sie mit **Parkstrecken-Monate** aus: im Web unter [[route:/settings/notifications|Benachrichtigungen]], in der Handy-App unter **Benachrichtigungen** im Tab **Du**.",
						"Die Abzeichen für Parkmonate zählen die Monate, in denen du eine Parkstrecke absolviert hast, bei 3, 6, 12 und 24 Monaten. Sie zählen absolvierte Strecken, nie Platzierungen.",
					],
				},
			],
		},
		{
			heading: "Wer auf den Listen erscheint",
			blocks: [
				{
					type: 'list',
					items: [
						"Du musst angemeldet sein, um die Listen zu sehen. Ohne Anmeldung zeigt eine Streckenseite trotzdem die Strecke und einen Link **Anmelden**.",
						"Eine Zeit aus einem Lauf, den andere nicht sehen können, wird ihnen nicht angezeigt.",
						"Du siehst keine Personen, die du blockiert hast, und sie sehen dich nicht.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Ein Lauf wird kurz nach dem Speichern oder Importieren auf unseren Servern mit den Parkstrecken abgeglichen, egal von welchem Gerät. Bis eine neue Zeit auf einer Liste erscheint, kann es ein paar Minuten dauern." },
			],
		},
	],
	sources: {
		title: "80ff9e4c22672c3e",
		summary: "a8d0d3cdf47ef5c6",
		"s0.heading": "216fc084817bfda9",
		"s0.b0": "c202f382c7f5c297",
		"s0.b1.i0": "a8567bc2512800d1",
		"s0.b1.i1": "420575263613791d",
		"s0.b1.i2": "d69fbf280d3b46a0",
		"s0.b1.i3": "a75477f7d5a5a5bc",
		"s0.b2": "a9aa6fec9968fc90",
		"s1.heading": "0026d1ddae689c8a",
		"s1.b0": "f00cd3cca5bfc92f",
		"s1.b1": "36e6dc7fd586b7d7",
		"s2.heading": "5ba4de4e9cb351a4",
		"s2.b0": "f5cb979a283038fa",
		"s2.b1": "6afb246fc0e80841",
		"s3.heading": "f90c634a3c69c00f",
		"s3.b0.i0": "8bab47facf52e4fd",
		"s3.b0.i1": "01322b98d3fa4762",
		"s3.b0.i2": "a26ad1f8b547015d",
		"s4.heading": "d62c88ea85d104ce",
		"s4.b0": "23512913978ca5c1",
		"s5.heading": "2158104d68549d3e",
		"s5.b0": "f8cebd1b6b6f6d5c",
		"s5.b1.i0": "95832d49c27d961e",
		"s5.b1.i1": "e5fd55e453a25d9a",
		"s5.b1.i2": "0220ee50a2c3ffc2",
		"s5.b1.i3": "3c988cac91d6d886",
		"s5.b1.i4": "9f0fedf00dcae221",
		"s6.heading": "b119ed9eec93efe3",
		"s6.b0.i0": "bee88a50dcbbbfa2",
		"s6.b0.i1": "25229437ce8179b8",
		"s6.b0.i2": "c95241619d2e3582",
		"s6.b1": "f0b47eeb5f542fe4",
	},
};
