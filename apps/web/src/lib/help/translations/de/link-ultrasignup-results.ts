import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'link-ultrasignup-results',
	title: 'Deine UltraSignup-Ergebnisse verknüpfen',
	summary: 'Finde dein UltraSignup-Profil über deinen Namen, bestätige, welche Person du bist, und importiere dann ein Ultra- oder Trail-Ergebnis aus dem Rennkalender.',
	sections: [
		{
			heading: 'Bevor du beginnst',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Der UltraSignup-Import ist nur im Web verfügbar und bleibt ausgeschaltet, bis er aktiviert wurde. Fehlt die UltraSignup-Karte unter Integrationen oder zeigt sie **UltraSignup-Import ist noch nicht verfügbar. parkrun und manuelles Einfügen funktionieren weiterhin.**, kannst du ein Ergebnis trotzdem hinzufügen, indem du es im Rennkalender einfügst.',
				},
				{
					type: 'p',
					text: 'UltraSignup verwaltet Anmeldungen und Ergebnisse vieler Trail- und Ultraläufe. Wenn du dein Profil einmal verknüpfst, musst du beim Importieren eines Ergebnisses nie wieder deinen Namen oder deine Startnummer eingeben.',
				},
			],
		},
		{
			heading: 'Dein Profil verknüpfen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne [[route:/settings/integrations|Integrationen]] in den Einstellungen und suche die UltraSignup-Karte.',
						'Gib unter **Dein UltraSignup-Profil finden** in **Vorname** und **Nachname** deinen Namen genau so ein, wie du dich zu Rennen anmeldest, und wähle dann **Mich finden**.',
						'UltraSignup listet alle Personen mit diesem Namen auf. Erkenne dich am Alter, an der Anzahl der Ergebnisse und an den letzten Rennen jeder Person.',
						'Wähle unter **Wer davon bist du?** bei deinem Eintrag **Das bin ich**.',
					],
				},
				{
					type: 'p',
					text: 'Die Karte zeigt jetzt **Verknüpft als** mit deinem Namen und deiner UltraSignup-Nummer. Hast du die falsche Person gewählt, wähle **Verknüpfung lösen** und suche erneut. Bereits importierte Läufe bleiben erhalten, wenn du die Verknüpfung löst.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Wenn du **Bei UltraSignup gibt es niemanden mit diesem Namen. Prüf die Schreibweise, unter der du läufst.** siehst, versuche die genaue Schreibweise aus deinen Rennanmeldungen, einschließlich eines zweiten Vornamens oder Bindestrichs.',
				},
			],
		},
		{
			heading: 'Ein Ergebnis aus dem Rennkalender importieren',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne [[route:/races|Rennen]] und suche das Rennen, das du gelaufen bist.',
						'Wähle **Mein Ergebnis importieren**. Der Import zeigt an, unter welchem Namen er importiert.',
						'Bestätige den Import. Übernommen wird nur dein eigenes Ergebnis für dieses Rennen, abgeglichen über die Renn-ID von UltraSignup und das Renndatum.',
					],
				},
				{
					type: 'p',
					text: 'Das Ergebnis kommt als Lauf mit deiner offiziellen Zeit und deinen Platzierungen an. Wenn du das Rennen selbst aufgezeichnet hast, öffne stattdessen diesen Lauf: Passt er zu einem Rennen im Kalender, fragt der Lauf, ob es dieses Rennen war, und **Ergebnis importieren** fügt das offizielle Ergebnis deinem vorhandenen Lauf hinzu, statt einen zweiten anzulegen.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Es werden nur Ergebnisse mit Zieleinlauf importiert, und ein Rennen, dessen ID oder Datum nicht passt, wird übersprungen statt geraten. Bisher sind nur sehr wenige UltraSignup-Rennen im Kalender, daher ist dein Rennen möglicherweise nicht aufgeführt; nutze stattdessen **Ergebnis einfügen** im Rennkalender.',
				},
				{
					type: 'p',
					text: 'Wenn du **Verknüpfe zuerst dein UltraSignup-Profil in den Einstellungen und importiere dann hier.** siehst, verknüpfe dein Profil wie oben beschrieben und komm zurück.',
				},
			],
		},
	],
	sources: {
		title: '1c3d3ccace74b014',
		summary: 'f2fca5922e80c09a',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '0c7ce54419de8a75',
		's0.b1': '44ce80029649ec21',
		's1.heading': '9585e27668c04a9f',
		's1.b0.i0': '5c97b00e1a40a36b',
		's1.b0.i1': 'c74c3876783d3d3e',
		's1.b0.i2': 'a2c9f8d1aa769e71',
		's1.b0.i3': '583ce1f06db5e7a3',
		's1.b1': '75c4a2aecaf4f626',
		's1.b2': 'a780f42937b826b1',
		's2.heading': '2beec2f1afabca9b',
		's2.b0.i0': 'b25aba40145c665f',
		's2.b0.i1': 'bd2e53852db627ea',
		's2.b0.i2': '6dce444ee6e264da',
		's2.b1': 'e5693507bec3f21c',
		's2.b2': '041b5d6a68e26cfe',
		's2.b3': '01220bce8ab2d8b5',
	},
};
