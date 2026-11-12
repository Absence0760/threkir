import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'park-courses',
	title: "Parkstrecken: Kontrollpunkte, Saisons und Bestenlisten",
	summary: "Wie eine Parkstrecke deinen Lauf misst, warum jeder Kontrollpunkt zählt, wann eine Saison beginnt und wie die Listen Schnellste und Meiste Läufe ranken.",
	sections: [
		{
			heading: "Was eine Parkstrecke ist",
			blocks: [
				{ type: 'p', text: "Eine Parkstrecke ist eine feste Zeitlaufstrecke auf einem Weg in einem State Park oder Nationalpark. Es gibt keinen Veranstalter und keinen Wettkampftag: Lauf sie, wann immer der Park geöffnet ist, und ein Lauf, der die ganze Strecke abdeckt, bekommt eine Zeit. Du findest sie unter **Jederzeit laufen** auf [[route:/races|Rennen & Strecken]], die nächsten zuerst, sobald du einen Ort festlegst, oder alle unter [[route:/parks|Parkstrecken]]." },
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
						"Standardmäßig zeigt sie dieses Jahr. Wähle **Gesamt** für die besten Zeiten aller Zeiten.",
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
		title: "c0967d2bf224e3d2",
		summary: "6a173631b44944bc",
		"s0.heading": "216fc084817bfda9",
		"s0.b0": "a96a5717c602367f",
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
		"s3.b0.i1": "c74b158f75754752",
		"s3.b0.i2": "a26ad1f8b547015d",
		"s4.heading": "d62c88ea85d104ce",
		"s4.b0": "23512913978ca5c1",
		"s5.heading": "b119ed9eec93efe3",
		"s5.b0.i0": "bee88a50dcbbbfa2",
		"s5.b0.i1": "25229437ce8179b8",
		"s5.b0.i2": "c95241619d2e3582",
		"s5.b1": "f0b47eeb5f542fe4",
	},
};
