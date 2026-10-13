import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'using-help',
	source: 'a9e53ac06c08edd3',
	title: 'Hilfe in der App finden',
	summary: 'Wo die Anleitungen zu finden sind, wie du sie durchsuchst und wie du von einem Bildschirm zur passenden Anleitung springst.',
	sections: [
		{
			heading: 'Hilfe öffnen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Wähle deinen Namen unten in der Seitenleiste. In einem schmalen Fenster schrumpft die Seitenleiste auf Symbole – wähle dann stattdessen den runden Avatar mit deinem Anfangsbuchstaben.',
						'Wähle im sich öffnenden Menü **Hilfe**.',
					],
				},
				{
					type: 'p',
					text: 'Die Übersichtsseite listet alle Anleitungen nach Thema auf. Die Chips unter **Anleitungen anzeigen für** grenzen die Liste auf die Anleitungen ein, die für dich geschrieben sind, etwa **Veranstalter** oder **Zuschauer**; **Alle** zeigt wieder alles an.',
				},
			],
		},
		{
			heading: 'Anleitungen durchsuchen',
			blocks: [
				{
					type: 'p',
					text: 'Gib oben unter [[route:/help|Hilfe]] ein oder zwei Wörter in **Anleitungen durchsuchen** ein und drücke **Suchen**. Anleitungen mit deinen Wörtern im Titel kommen zuerst, dann solche, die sie in der Zusammenfassung erwähnen, dann der Rest.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Groß- und Kleinschreibung sowie Akzente spielen keine Rolle, *cafe* findet also *Café*. Jedes eingegebene Wort muss irgendwo in einer Anleitung vorkommen, damit sie aufgelistet wird.',
				},
			],
		},
		{
			heading: 'Hilfe direkt vom Bildschirm aus',
			blocks: [
				{
					type: 'p',
					text: 'Ein Bildschirm mit Anleitung zeigt neben seinem Titel einen Link **So funktioniert das**. Er öffnet die Anleitung für diesen Bildschirm; gibt es mehrere passende Anleitungen, öffnet er eine kurze Liste zur Auswahl.',
				},
				{
					type: 'p',
					text: 'Manche Karten und Einstellungen haben einen kleinen runden *i*-Button. Er erklärt die Funktion in ein, zwei Sätzen, und wenn eine Anleitung weiter ins Detail geht, endet er mit **Anleitung lesen**.',
				},
			],
		},
		{
			heading: 'Eine Anleitung lesen',
			blocks: [
				{
					type: 'list',
					items: [
						'Die Badges unter dem Titel zeigen, für welche Apps die Anleitung gilt und ob du zuerst etwas brauchst, etwa Pro oder eine Admin-Rolle in einem Club.',
						'**Auf dieser Seite** listet die Abschnitte einer längeren Anleitung auf und springt zum gewählten Abschnitt.',
						'**Verwandte Anleitungen** am Ende verweist auf das, was du wahrscheinlich als Nächstes brauchst.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Anleitungen werden in der Sprache angezeigt, auf die die App eingestellt ist. Eine Anleitung, die noch nicht in diese Sprache übersetzt ist, wird auf Englisch angezeigt, mit einem entsprechenden Hinweis oben.',
				},
			],
		},
	],
};
