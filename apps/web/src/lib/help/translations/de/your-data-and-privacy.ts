import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'your-data-and-privacy',
	source: '71682d547c6ae11d',
	title: 'Deine Daten und deine Privatsphäre',
	summary: 'Sieh nach, was andere sehen können, wähle, wer neue Läufe sieht, lade alles herunter, was wir über dich speichern, und lösche dein Konto.',
	sections: [
		{
			heading: 'Was andere sehen können',
			blocks: [
				{
					type: 'list',
					items: [
						'Deine Profilseite mit Anzeigenamen, Bild, Follower-Zahlen und deinen öffentlichen Läufen kann jeder öffnen, der ihren Link hat.',
						'Läufe, die du öffentlich machst, erscheinen in deinem Profil und im Feed. Private Läufe sind nur für dich sichtbar.',
						'Deine Mitgliedschaft in einem öffentlichen Club und alles, was du dort postest, können alle sehen, die den Club sehen können.',
						'Solange du einen Live-Link teilst, kann jeder mit dem Link den laufenden Lauf sehen.',
					],
				},
				{
					type: 'p',
					text: 'Datenschutzzonen kürzen Anfang und Ende deiner Aufzeichnungen überall dort, wo andere sie sehen. Siehe [[guide:privacy-zones|Dein Zuhause mit Datenschutzzonen verbergen]].',
				},
			],
		},
		{
			heading: 'Wählen, wer neue Läufe sieht',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne im Web in den Einstellungen [[route:/settings/privacy|Datenschutz & Teilen]] und wähle eine **Standardsichtbarkeit für neue Läufe**. In der Handy-App ist es **Standard-Datenschutz für Läufe** unter **Voreinstellungen** im Tab **Du**.',
						'Um einen einzelnen Lauf später zu ändern, öffne ihn und nutze **Öffentlich machen** oder **Privat machen**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Nur **Öffentlich** macht neue Läufe für andere sichtbar. Läufe haben noch keine Einstellung „nur Follower“ – wählst du Follower als Standard, bleiben neue Läufe privat, und deine Follower sehen sie nicht.',
				},
				{
					type: 'list',
					items: [
						'**Mich in der Namenssuche anzeigen**: Schalte das aus, damit dein Konto nicht in Namenssuchen erscheint. Dein Profil und deine öffentlichen Läufe kann trotzdem jeder öffnen, der den Link hat.',
						'**Mich unter „Läufer in der Nähe“ anzeigen**, wo angeboten: standardmäßig aus. Ist es an, können dich Läufer in der Nähe des von dir festgelegten Gebiets finden. Gespeichert wird nur ein ungefähres Gebiet, nie dein Live-Standort.',
					],
				},
			],
		},
		{
			heading: 'Deine Daten herunterladen',
			blocks: [
				{
					type: 'p',
					text: 'Öffne im Web in den Einstellungen **Konto**. Die Handy-App bietet dieselben Optionen unter **Konto** im Tab **Du**.',
				},
				{
					type: 'list',
					items: [
						'**Vollständiges Kontoarchiv herunterladen** (auf dem Handy **Kontoexport**): alles, was wir über dich speichern, einschließlich Coach-Chats, Nachrichten, Integrationen und Sicherheitskontakten, als eine ZIP-Datei. Es wird auf unserem Server erstellt, du kannst die Seite also schließen und später wiederkommen. Ein fertiger Export wird 7 Tage lang aufbewahrt.',
						'**Vollständiges Backup herunterladen** (auf dem Handy **Vollständiges Backup**): jeder Lauf mit seinem GPS-Track sowie deine Routen, dein Profil und deine Einstellungen in einer Datei, die du später mit **Aus Backup wiederherstellen** zurückspielen kannst.',
						'**Cloud-Export (GPX-ZIP)**: eine GPX-Datei pro Lauf, mit Herzfrequenz, bereit zum Import in andere Apps. Kostenlose Konten können zweimal pro Stunde exportieren, Pro-Konten achtmal.',
						'**Alle Läufe exportieren (CSV)** (auf dem Handy **Läufe als CSV exportieren**): eine Zeile pro Lauf für eine Tabellenkalkulation, ohne GPS-Tracks.',
					],
				},
			],
		},
		{
			heading: 'Dein Konto löschen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Lade zuerst alles herunter, was du behalten möchtest. Das Löschen kann nicht rückgängig gemacht werden.',
						'Öffne im Web in den Einstellungen **Konto** und wähle **Konto löschen** unter **Gefahrenzone**. Öffne in der Handy-App **Konto** im Tab **Du** und tippe auf **Konto löschen**.',
						'Gib zur Bestätigung LÖSCHEN ein und wähle dann im Web **Mein Konto löschen** oder in der App **Löschen**.',
					],
				},
				{
					type: 'p',
					text: 'Dadurch werden dein Konto, deine Läufe, Routen, Aufzeichnungen, Club-Mitgliedschaften und Einstellungen dauerhaft von unseren Servern entfernt. Auf einem Handy bleiben Läufe, die auf dem Gerät selbst gespeichert sind, dort, bis du dich als jemand anderes anmeldest oder die App entfernst.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Du kommst nicht in die App? [[route:/delete-account|Konto löschen]] erklärt, wie du die Löschung ohne die App beantragen kannst.',
				},
			],
		},
	],
};
