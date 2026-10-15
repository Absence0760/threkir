import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'log-a-meal-from-a-photo',
	title: 'Eine Mahlzeit per Foto eintragen',
	summary: 'Fotografiere deinen Teller, lass Threkir schätzen, was darauf ist, und prüfe und bearbeite jeden Eintrag, bevor er in dein Ernährungstagebuch kommt.',
	sections: [
		{
			heading: 'Bevor du anfängst',
			blocks: [
				{
					type: 'list',
					items: [
						'Das Eintragen per Foto gehört zu Pro. Essen von Hand einzutragen bleibt kostenlos.',
						'Es nutzt KI und setzt deshalb den aktuellen KI-Hinweis voraus. Wirst du gebeten, ihn zu akzeptieren, öffne Einstellungen → Konto und akzeptiere ihn dort.',
						'Das Foto wird nur genutzt, um zu schätzen, was auf dem Teller ist. Standort- und Kameradaten werden vor dem Senden entfernt, und Threkir behält das Foto nicht.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Es ist eventuell noch nicht eingeschaltet. Siehst du **Aus einem Foto eintragen** nicht, ist es für dich nicht verfügbar.',
				},
			],
		},
		{
			heading: 'Im Web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne [[route:/nutrition|Ernährung]] und wähle **Essen erfassen**, dann **Aus einem Foto eintragen**.',
						'Wähle **Foto auswählen** und such ein Bild deiner Mahlzeit aus.',
						'Füge bei Bedarf eine **Notiz (optional)** hinzu, etwa halbe Portion.',
						'Wähle **Schätzen**.',
					],
				},
			],
		},
		{
			heading: 'In der Handy-App',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne **Fitness**, wähle den Tab **Ernährung** und tippe auf die Kamera-Schaltfläche **Aus einem Foto eintragen**.',
						'Tippe auf **Foto aufnehmen** oder **Foto auswählen**.',
						'Füge bei Bedarf eine **Notiz (optional)** hinzu und tippe dann auf **Schätzen**.',
					],
				},
			],
		},
		{
			heading: 'Vor dem Speichern prüfen',
			blocks: [
				{
					type: 'p',
					text: 'Unter **Vor dem Speichern prüfen** steht jedes Lebensmittel mit Kalorien, Eiweiß, Kohlenhydraten und Fett. Das sind Schätzungen, also prüfe sie.',
				},
				{
					type: 'list',
					items: [
						'Ändere jeden Namen und jede Zahl, die falsch aussieht. Einträge mit **Unsichere Schätzung** lohnen am ehesten einen zweiten Blick.',
						'Entferne alles, was nicht auf deinem Teller ist.',
						'Wähle die **Mahlzeit**, zu der das Essen gehört.',
						'Wähle **Einträge speichern**, um den Rest in dein Ernährungstagebuch aufzunehmen. Vorher wird nichts gespeichert.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Wird kein Essen erkannt oder hast du in der letzten Stunde viele Fotos eingetragen, trag die Mahlzeit wie gewohnt von Hand ein.',
				},
			],
		},
	],
	sources: {
		title: 'bbdc9660a287e7c1',
		summary: 'aeef5fef4857acdc',
		's0.heading': '74e492d5d0df0bab',
		's0.b0.i0': 'd03e553125a96101',
		's0.b0.i1': 'ad91a1f646fd4777',
		's0.b0.i2': '63338ba4abc28ffc',
		's0.b1': '6791908473990cc8',
		's1.heading': '1e1b85a2667ca4d5',
		's1.b0.i0': '01eae5b5a4e98d0f',
		's1.b0.i1': '29b05255de9bf718',
		's1.b0.i2': 'e1f5d3b8c8fe13e4',
		's1.b0.i3': '945cfae0c52315dc',
		's2.heading': 'f21eaef94c685b5c',
		's2.b0.i0': 'c010f5524e29e935',
		's2.b0.i1': '788614966879c6fe',
		's2.b0.i2': 'c74ad67ce20e5723',
		's3.heading': 'a87450ed45241ef4',
		's3.b0': 'a770f2d0fc04e051',
		's3.b1.i0': 'ed3985f616eca37f',
		's3.b1.i1': '88c6d0416eae03ab',
		's3.b1.i2': 'ffc4a5ff20130b13',
		's3.b1.i3': '8f4ca5857c9f1f76',
		's3.b2': '8fea5a4dccf15c27',
	},
};
