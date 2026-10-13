import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'what-pro-includes',
	source: 'd06d482fd22c314b',
	title: 'Was Pro umfasst',
	summary: 'Jeder Bildschirm in Threkir ist kostenlos; Pro erhöht dein Kontingent beim KI-Coach und stellt einige Hintergrundaufgaben in der Warteschlange nach vorn.',
	sections: [
		{
			heading: 'Was kostenlos bleibt',
			blocks: [
				{
					type: 'p',
					text: 'Nichts in der App ist hinter Pro gesperrt. Kostenlose Konten bekommen unbegrenzte Aufzeichnung auf Handy und Uhr, Routen, Trainingspläne samt der Zahlen dahinter, Clubs und Events, den Social-Feed, Sicherheitskontakte, Importe und Backups.',
				},
			],
		},
		{
			heading: 'Was Pro hinzufügt',
			blocks: [
				{
					type: 'list',
					items: [
						'**KI-Coach — 10/Tag**: zehn Coach-Nachrichten pro Tag statt zwei. Der Zähler wird um Mitternacht UTC zurückgesetzt.',
						'Längere, gründlichere Coach-Antworten, die mehr deiner Läufe berücksichtigen können.',
						'**Vorrangiges Map-Matching**: Deine GPS-Aufzeichnungen werden vor denen kostenloser Konten an Straßen ausgerichtet und sind dadurch früher fertig.',
						'**Vorrangige Cloud-Exporte**: bis zu 8 GPX-Paket-Exporte pro Stunde statt 2.',
						'**Server-Routengenerierung**: Rundkurse, die auf dem echten Straßennetz berechnet werden, wenn du eine Route nach Distanz generierst. Kostenlose Konten bekommen weiterhin Rundkurs-Generierung, berechnet im Browser.',
						'Ausführlichere Routenbeschreibungen: Auf der Seite einer Route macht **Mit KI verbessern** aus der Standardbeschreibung einen ausführlicheren Absatz.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Einige davon hängen von Diensten ab, die womöglich noch nicht eingeschaltet sind. Die Pro-Karte unter [[route:/settings/upgrade|Pro & Unterstützung]] listet nur auf, was heute funktioniert; steht dort **Pro schaltet den KI-Coach frei – demnächst verfügbar.**, kann Pro noch nicht gekauft werden.',
				},
			],
		},
		{
			heading: 'So bekommst du Pro',
			blocks: [
				{
					type: 'p',
					text: 'Pro ist ein Monats- oder Jahresabo; die Pro-Karte zeigt die aktuellen Preise. Wo du es kaufen kannst, hängt von deinem Gerät ab:',
				},
				{
					type: 'list',
					items: [
						'Öffne auf einem iPhone im Tab **Du** den Punkt **Pro & Support** und schließe das Abo über den App Store ab.',
						'Öffne im Web in den Einstellungen [[route:/settings/upgrade|Pro & Unterstützung]]. Steht dort **Ein Abo direkt im Web kommt bald.**, schließ das Abo stattdessen in der iPhone-App ab.',
					],
				},
				{
					type: 'p',
					text: 'Pro gehört zu deinem Konto, nicht zu deinem Gerät – ein auf einem Gerät gekauftes Abo funktioniert also überall, wo du dich anmeldest.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Die Preise sind in US-Dollar, und der App Store berechnet den für dein Land festgelegten Preis. Manche Länder und Zahlungsmethoden kann unser Zahlungsdienstleister nicht bedienen.',
				},
			],
		},
		{
			heading: 'Verwalten oder kündigen',
			blocks: [
				{
					type: 'list',
					items: [
						'Kündige oder ändere dein Abo dort, wo du es abgeschlossen hast: im App Store, im Play Store oder im Abrechnungsportal im Web. **Abo verwalten** bringt dich dorthin.',
						'Tippe auf einem neuen Handy unter **Pro & Support** auf **Käufe wiederherstellen**, um ein bestehendes Abo zu übernehmen.',
						'Lieber ein einmaliger Beitrag? **Spenden** findest du auf derselben Seite.',
					],
				},
			],
		},
	],
};
