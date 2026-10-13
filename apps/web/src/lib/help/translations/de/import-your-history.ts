import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'import-your-history',
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
	sources: {
		title: '078b29389d32808d',
		summary: '440ddd94eca0b542',
		's0.heading': '69858eb69781e59e',
		's0.b0.i0': '92767a2a2bf7c191',
		's0.b0.i1': '8c05e0ad16ddb8c2',
		's0.b0.i2': '828e8880f5239f1c',
		's0.b1': '4302ec5e7767e8ab',
		's1.heading': '8abf228027d2a4fd',
		's1.b0': 'cf7faaa4679e66f2',
		's1.b1.i0': '9e771e203c299ace',
		's1.b1.i1': 'a6d02ee139faa051',
		's1.b1.i2': '0212bc406356fd62',
		's2.heading': 'f3f586814898940a',
		's2.b0': '25c859eb00073fae',
		's2.b1.i0': 'f82bc798e8ec1b4e',
		's2.b1.i1': '21d706b389df8c6a',
		's2.b1.i2': '69a212e6bb305cfc',
		's2.b2': '7d501c5e8de3d96e',
		's3.heading': '8b42dffcf7f0d635',
		's3.b0': '0dba61c98d441dad',
		's3.b1': '5dbef244bd55926e',
		's4.heading': '35509c7701b9dabc',
		's4.b0': '26a0daac64b29af6',
		's4.b1': '69e6cfdbe0110cea',
	},
};
