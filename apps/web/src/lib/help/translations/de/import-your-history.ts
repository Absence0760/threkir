import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'import-your-history',
	source: 'ffbec728934ee1d4',
	title: 'Deine Laufhistorie importieren',
	summary: 'Hol deine früheren Läufe aus Strava, einem Garmin-Export oder der Gesundheits-App deines Handys und erfahre, was mit GPX-Dateien passiert.',
	sections: [
		{
			heading: 'Strava für aktuelle und neue Läufe verbinden',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne im Web [[route:/settings/integrations|Integrationen]] in den Einstellungen und wähle auf der Strava-Karte **Verbinden**, oder öffne in der Handy-App **Integrationen** im Tab **Du** und tippe auf Strava.',
						'Melde dich bei Strava an und erlaube den Zugriff.',
						'Deine Läufe, Spaziergänge und Wanderungen der letzten 90 Tage werden übernommen, und neue Strava-Aktivitäten folgen automatisch.',
					],
				},
				{
					type: 'p',
					text: 'Wähle **Jetzt synchronisieren**, um erneut abzurufen. Im Web reicht **Wie weit zurück synchronisieren** bis zu einem Jahr zurück.',
				},
			],
		},
		{
			heading: 'Dein gesamtes Strava-Archiv übernehmen',
			blocks: [
				{
					type: 'p',
					text: 'Die Strava-Verbindung erreicht nur aktuelle Aktivitäten. Für eine jahrelange Historie nutze einen Strava-Datenexport.',
				},
				{
					type: 'steps',
					items: [
						'Geh in Strava zu Einstellungen, Mein Konto und fordere dein Archiv an. Strava schickt dir per E-Mail einen Link zu einer ZIP-Datei.',
						'Öffne im Web [[route:/settings/integrations|Integrationen]], suche **Sammelimport aus einem Strava-Export** und wähle **Strava-Export-ZIP auswählen**. Öffne in der Handy-App **Konto** im Tab **Du**, dann **Aus einer anderen App importieren**, und tippe auf **Strava-ZIP importieren**.',
						'Warte, bis der Import abgeschlossen ist. Läufe, die du schon hast, etwa aus deiner Strava-Verbindung, werden übersprungen, du kannst ihn also gefahrlos erneut ausführen.',
					],
				},
			],
		},
		{
			heading: 'Garmin- und FIT-Dateien',
			blocks: [
				{
					type: 'p',
					text: 'Eine automatische Verbindung mit Garmin Connect gibt es noch nicht, weil Garmin sie erst genehmigen muss. Bis dahin kannst du Garmin-Dateien im Web importieren.',
				},
				{
					type: 'steps',
					items: [
						'Exportiere in Garmin Connect entweder eine einzelne Aktivität mit „Original exportieren“, was dir eine .fit-Datei liefert, oder fordere deinen vollständigen Datenexport über die Garmin-Kontoverwaltung an.',
						'Öffne im Web [[route:/settings/integrations|Integrationen]], suche **Sammelimport aus einem Garmin-Export** und wähle **Garmin-Export auswählen**.',
						'Wähle die .fit-Datei oder die ZIP-Datei aus. Bereits importierte Aktivitäten werden übersprungen.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Unter Android können Trainings, die deine Garmin-, Samsung- oder Fitbit-App in Health Connect schreibt, ebenfalls über **Aus einer anderen App importieren** übernommen werden. Auf einem iPhone liest dieselbe Karte Apple Health.',
				},
			],
		},
		{
			heading: 'GPX und andere Einzeldateien',
			blocks: [
				{
					type: 'p',
					text: 'Eine einzelne GPX-, KML-, KMZ-, GeoJSON- oder TCX-Datei wird als Route importiert, der du folgen kannst, nicht als Lauf in deinem Verlauf. Öffne [[route:/routes|Routen]] im Web oder die Routenliste in der App und importiere sie dort.',
				},
				{
					type: 'p',
					text: 'GPX- und TCX-Dateien in einer ZIP-Datei aus einem Strava- oder Garmin-Export werden als Läufe gelesen. Mit den oben beschriebenen Sammelimporten fügst du also eine Historie aus GPX-Aktivitäten hinzu.',
				},
			],
		},
		{
			heading: 'Wenn etwas nicht importiert wird',
			blocks: [
				{
					type: 'p',
					text: 'Wenn einige Aktivitäten ausgelassen werden, listet der Import jede einzelne mit Grund auf, etwa eine abgebrochene Verbindung oder eine Datei, die nicht gelesen werden konnte. Führe den Import erneut aus, um es noch einmal zu versuchen: Alles, was bereits angekommen ist, wird übersprungen, sodass nichts doppelt angelegt wird.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Importierte Läufe folgen deinem Standard-Datenschutz für Läufe. Prüfe ihn also vor einem großen Import, wenn nicht auf einen Schlag Läufe aus mehreren Jahren öffentlich erscheinen sollen. Siehe [[guide:your-data-and-privacy|Deine Daten und deine Privatsphäre]].',
				},
			],
		},
	],
};
