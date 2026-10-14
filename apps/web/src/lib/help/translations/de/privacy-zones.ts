import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'privacy-zones',
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
				{
					type: 'illustration',
					id: 'privacy-zones',
					alt: 'Eine Routenlinie beginnt an einem Haus in einem Kreis. Der Teil innerhalb des Kreises ist für andere verborgen, sodass die Linie, die sie sehen, erst am Rand des Kreises beginnt.',
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
	sources: {
		title: 'd9e7d40ed8ec1d93',
		summary: '04c4913e2da59def',
		's0.heading': '27ee9eff5654fc40',
		's0.b0': '0786f273bb90019e',
		's0.b1.i0': 'ae791e6bb37bf75e',
		's0.b1.i1': 'f895445f10db7b57',
		's0.b1.i2': '591dec4de03df2a3',
		's1.heading': 'cc3973572fe81b73',
		's1.b0.i0': 'a9f7c5a79d8779f0',
		's1.b0.i1': 'de234d8646b8454f',
		's1.b0.i2': '35c82b7aef764872',
		's1.b0.i3': '1d8fc63d18b8641a',
		's1.b0.i4': '150b03da903ccf27',
		's1.b1': 'b395019ec1836f1e',
		's2.heading': 'd50fe7d487cde78b',
		's2.b0.i0': '0f37a464ec66cdc7',
		's2.b0.i1': 'e3478863d167e8fe',
		's2.b0.i2': 'ca9cc061ff309425',
		's2.b0.i3': '2f1655078cb4ae12',
		's2.b1': 'cb30c404ac96aa57',
		's3.heading': 'ea3ab9efa7240662',
		's3.b0.i0': '9184e7f4329c71d3',
		's3.b0.i1': '7e6aff2443fca79b',
		's3.b0.i2': '2d441105a1624ed1',
		's3.b1': '20c32d436fe0799c',
		's0.b2': '9bfc49abe8494ae1',
	},
};
