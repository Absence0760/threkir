import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'record-your-first-run',
	source: '9587d8580082759d',
	title: 'Deinen ersten Lauf aufzeichnen',
	summary: 'Starte einen Lauf auf deinem Handy, pausiere und beende ihn sicher, bekomm ein gutes GPS-Signal und sieh, was danach gespeichert wird.',
	sections: [
		{
			heading: 'Aufzeichnung starten',
			blocks: [
				{
					type: 'p',
					text: 'Läufe werden in der Handy-App oder auf einer Uhr aufgezeichnet. Die Web-App zeigt deine Läufe an, kann aber keinen aufzeichnen.',
				},
				{
					type: 'steps',
					items: [
						'Tippe auf die große Schaltfläche in der Mitte der unteren Leiste. Sie zeigt **Laufen** oder, wenn du Gym oder Ernährung eingeschaltet hast, **Erfassen** – wähle in dem Fall **Lauf erfassen**.',
						'Tippe auf **START**. Beim ersten Mal fragt dein Handy nach Zugriff auf deinen Standort: Erlaube ihn, sonst zeichnet der Lauf nur die Zeit auf, ohne Distanz und Karte.',
						'Ein Countdown von drei Sekunden läuft, während sich das GPS einpendelt, dann startet die Uhr.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Wähle unter Android für den Standort **Immer zulassen**. Mit Zugriff nur bei geöffneter App wird die Distanz, die du bei ausgeschaltetem Bildschirm zurücklegst, nicht gezählt, obwohl die Uhr weiterläuft.',
				},
			],
		},
		{
			heading: 'Pausieren und Beenden',
			blocks: [
				{
					type: 'p',
					text: 'Es gibt keine Auto-Pause: Die Uhr läuft, bis du sie pausierst. Nutze die Pause-Taste für einen Halt, der nicht in deine Zeit einfließen soll, und die Fortsetzen-Taste, um weiterzulaufen.',
				},
				{
					type: 'p',
					text: 'Ohne Pause an einer Ampel zu stehen schadet nicht. Nach dem Lauf lässt die Zeit in **Bewegung** die Abschnitte weg, in denen du stillgestanden hast, und dein Tempo wird aus der Bewegungszeit berechnet.',
				},
				{
					type: 'steps',
					items: [
						'Zum Beenden halte die Stopp-Taste gedrückt. Der Hinweis lautet **Zum Stoppen halten**, damit ein versehentliches Tippen in der Tasche den Lauf nicht beendet.',
						'Die Zusammenfassung **Lauf beendet** zeigt deine Distanz, die **Zeit**, die Zeit in **Bewegung**, dein Tempo und alle weiteren Werte, die dein Handy gemessen hat.',
						'Tippe auf **Fertig**, um zum Startbildschirm zurückzukehren.',
					],
				},
			],
		},
		{
			heading: 'Ein gutes GPS-Signal bekommen',
			blocks: [
				{
					type: 'list',
					items: [
						'Starte draußen, abseits hoher Gebäude und dichter Bäume, damit der Countdown freie Sicht zum Himmel hat.',
						'Wenn du **GPS-Signal verloren — geh ins Freie** siehst, lauf weiter: Die Uhr läuft weiter, und die Distanz wird wieder erfasst, sobald das Signal zurück ist.',
						'**Schwaches GPS — Distanz pausiert** bedeutet, dass deine Position zu ungenau ist, um gezählt zu werden. Die Distanz wird wieder erfasst, sobald sich das Signal verbessert.',
						'Lass die Standortdienste eingeschaltet und den Energiesparmodus für die App ausgeschaltet, damit dein Handy die Aufzeichnung im Hintergrund nicht stoppt.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Wenn die App mitten im Lauf geschlossen wird, öffne sie erneut: Du wirst **Lauf fortsetzen?** gefragt und kannst fortsetzen, jetzt beenden oder den Lauf verwerfen.',
				},
			],
		},
		{
			heading: 'Was gespeichert wird',
			blocks: [
				{
					type: 'p',
					text: 'Wenn du stoppst, wird der Lauf zuerst auf deinem Handy gespeichert und dann in dein Konto hochgeladen. Die Zusammenfassung zeigt **Synchronisiert**, sobald er sicher in der Cloud ist, oder **Offline gespeichert.**, wenn du abgemeldet bist. Ein Lauf, der nicht hochgeladen werden konnte, bleibt auf dem Handy und wird später erneut hochgeladen.',
				},
				{
					type: 'list',
					items: [
						'Distanz, Gesamtzeit, Bewegungszeit und Tempo.',
						'Dein GPS-Track, aus dem Karte und Splits entstehen.',
						'Höhe, Schritte und Herzfrequenz, wenn du einen Herzfrequenz-Brustgurt gekoppelt hast.',
					],
				},
				{
					type: 'p',
					text: 'Wer den Lauf sehen kann, richtet sich nach deiner Einstellung **Standard-Datenschutz für Läufe**, die du danach für jeden einzelnen Lauf ändern kannst. Um zu verbergen, wo du wohnst, richte [[guide:privacy-zones|Datenschutzzonen]] ein, bevor du etwas teilst.',
				},
			],
		},
	],
};
