import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'privacy-zones',
	source: 'c3af798bbfeb6e83',
	title: 'Dein Zuhause mit Datenschutzzonen verbergen',
	summary: 'Zieh einen Kreis um dein Zuhause, deine Arbeit oder einen anderen Ort, damit Start und Ende deiner Läufe und Routen darin für alle außer dir verborgen sind.',
	sections: [
		{
			heading: 'Was eine Datenschutzzone bewirkt',
			blocks: [
				{
					type: 'p',
					text: 'Eine Datenschutzzone ist ein Kreis auf der Karte. Beginnt oder endet ein Lauf oder eine Route darin, wird dieser Teil des Tracks abgeschnitten, bevor jemand anderes ihn sieht, sodass die Linie am Rand des Kreises zu beginnen und zu enden scheint.',
				},
				{
					type: 'list',
					items: [
						'Sie gilt für das, was andere sehen: geteilte Läufe und Routen, dein öffentliches Profil, den Feed, Heatmaps und die Live-Tracking-Seite.',
						'Sie gilt für bereits aufgezeichnete Läufe ebenso wie für neue, denn der Track wird jedes Mal gekürzt, wenn jemand anderes ihn ansieht.',
						'Du selbst siehst immer deinen vollständigen Track, und Dateien, die du für dich exportierst, enthalten ebenfalls den vollständigen Track.',
					],
				},
			],
		},
		{
			heading: 'Eine Zone im Web hinzufügen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne [[route:/settings/privacy|Datenschutz & Teilen]] in den Einstellungen.',
						'Wähle unter **Datenschutzzonen** die Option **Zone hinzufügen**.',
						'Klicke auf die Stelle der Karte, an der der Mittelpunkt der Zone liegen soll, oder wähle **Aktuellen Standort verwenden**, und zieh dann die Markierung zur Feinjustierung.',
						'Lege den **Radius** fest. Alles innerhalb des roten Kreises wird in öffentlichen Freigaben verborgen.',
						'Wähle **Zone hinzufügen**. Die Zone wird sofort gespeichert.',
					],
				},
				{
					type: 'p',
					text: 'Um eine Zone zu löschen, wähle daneben **Entfernen** und bestätige. Wird eine Zone entfernt, ist dieser Bereich in öffentlichen Freigaben wieder sichtbar.',
				},
			],
		},
		{
			heading: 'Eine Zone in der Handy-App hinzufügen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne den Tab **Du**, dann **Voreinstellungen**, und tippe unter **Datenschutz & Teilen** auf **Datenschutzzonen**.',
						'Tippe auf die Karte, um eine Zone zu setzen. Mit **Orte suchen…** oder **Mich orten** verschiebst du die Karte vorher.',
						'Stell den Schieberegler **Radius** ein.',
						'Tippe auf **Speichern**. Bis du speicherst, ändert sich nichts.',
					],
				},
				{
					type: 'p',
					text: 'Um eine Zone zu löschen, tippe auf ihre Markierung und bestätige, oder entferne mit **Alle löschen** alle Zonen auf einmal. Tippe dann auf **Speichern**; wird eine Zone entfernt, ist dieser Bereich in öffentlichen Freigaben wieder sichtbar.',
				},
			],
		},
		{
			heading: 'Eine gute Zone wählen',
			blocks: [
				{
					type: 'list',
					items: [
						'Setze den Mittelpunkt der Zone in die Nähe deiner Haustür, nicht genau darauf, damit der Rand des Kreises nicht direkt auf dein Haus zeigt.',
						'Mach sie groß genug, um ein paar Straßen abzudecken. Ein winziger Kreis kann dein Zuhause trotzdem verraten.',
						'Lege eine Zone für jeden Ort an, an dem du regelmäßig startest, etwa bei der Arbeit oder bei Freunden.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Zonen kürzen nur die Linie auf der Karte. Titel, Beschreibung und Fotos eines Laufs werden so angezeigt, wie du sie geschrieben hast – lass Adressen dort also weg.',
				},
			],
		},
	],
};
