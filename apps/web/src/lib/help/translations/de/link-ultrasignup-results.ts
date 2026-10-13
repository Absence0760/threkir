import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'link-ultrasignup-results',
	source: '0ad8552abbcc91f8',
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
};
