import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'create-a-club',
	title: 'Einen Club gründen',
	summary: 'Gründe einen Club für deine Laufgruppe, leg fest, wer ihn finden kann und wie man beitritt, und veröffentliche dann dein erstes Event.',
	sections: [
		{
			heading: 'Im Web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne [[route:/social|Community]] und wähle den Tab **Clubs**.',
						'Wähle **Club erstellen**.',
						'Fülle **Name** aus. Mitglieder suchen den Club unter diesem Namen, und die Webadresse des Clubs wird beim Erstellen daraus gebildet. Wenn du den Club später umbenennst, ändert sich diese Adresse nicht.',
						'Füge auf Wunsch eine **Beschreibung** und einen **Ort** hinzu. Beides ist optional, aber Stadt und Land unter **Ort** helfen Läufern in der Nähe, dich zu finden, wenn sie in ihrer eigenen Region suchen.',
						'Wähle eine **Sichtbarkeit**: Clubs mit **Öffentlich** erscheinen unter **Entdecken**, Clubs mit **Privat** sind verborgen, und man kann ihnen nur über einen Einladungslink beitreten.',
						'Wähle unter **Wer kann beitreten?** die Option **Jeder kann beitreten**, **Freigabe erforderlich** oder **Nur mit Einladung**.',
						'Hake **Eine Bestätigung der Aktivitätsrisiken für den Beitritt verlangen** an, wenn jedes neue Mitglied bestätigen soll, dass es die Risiken von Gruppenläufen versteht. Das lässt sich nur jetzt festlegen, während der Club erstellt wird.',
						'Wähle **Club erstellen**. Du gelangst auf die Seite des neuen Clubs und bist sein Inhaber.',
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
						'Öffne den Tab **Sozial** und wähle **Clubs**.',
						'Tippe auf **Neuer Club**.',
						'Fülle **Name** aus und optional **Beschreibung (optional)** und **Standort (optional)**.',
						'Wähle **Öffentlich** oder **Privat** und dann eine **Beitrittsregel**: **Offen — jeder kann beitreten**, **Anfrage — Admins genehmigen** oder **Nur mit Einladung**.',
						'Tippe auf **Erstellen**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Die Bestätigung der Aktivitätsrisiken sowie die Website und die Social-Media-Links des Clubs lassen sich nur im Web festlegen.',
				},
			],
		},
		{
			heading: 'Nach dem Erstellen',
			blocks: [
				{
					type: 'p',
					text: 'Deine Club-Seite hat Tabs für **Feed**, **Events**, **Routen**, **Vorlagen**, **Fotos** und **Mitglieder**. Als Inhaber kannst du Neuigkeiten im Feed posten, Events hinzufügen und Mitglieder verwalten.',
				},
				{
					type: 'list',
					items: [
						'Um Name, Beschreibung, Sichtbarkeit, Beitrittsregel oder Links später zu ändern, öffne den Club im Web und wähle **Club bearbeiten**.',
						'Um deinen ersten Gruppenlauf hinzuzufügen, wähle im Web **Neues Event** oder tippe in der Handy-App im Tab **Events** auf **Event erstellen**.',
						'Wie du Leute dazuholst, steht in [[guide:invite-members-and-roles|Mitglieder einladen und Rollen vergeben]].',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Das Löschen eines Clubs entfernt alle seine Events, Beiträge und Mitglieder für alle, und es kann nicht rückgängig gemacht werden.',
				},
			],
		},
	],
	sources: {
		title: 'ff916040a4a088ae',
		summary: '90e58c1ce029b9f8',
		's0.heading': '1e1b85a2667ca4d5',
		's0.b0.i0': '81704e449355f8cb',
		's0.b0.i1': 'acfe56320dd5fa86',
		's0.b0.i2': '8f5ed6e368636764',
		's0.b0.i3': '0b33c70ca105f651',
		's0.b0.i4': 'ac21a20e9c83b3b8',
		's0.b0.i5': '7d3a8a5850778a1a',
		's0.b0.i6': '8a20a1b7087f8a35',
		's0.b0.i7': '019cb8b4c6074fbe',
		's1.heading': 'f21eaef94c685b5c',
		's1.b0.i0': 'ecd88baa3a8b6dfe',
		's1.b0.i1': 'fe76ba21da4f039b',
		's1.b0.i2': '2cc7185287318c16',
		's1.b0.i3': '4bd544b513ee23e9',
		's1.b0.i4': '42d0b5b43ab9db8b',
		's1.b1': '8cc57f936798f492',
		's2.heading': '6620415f4bf77118',
		's2.b0': 'a1a749aa3fcf7a85',
		's2.b1.i0': 'a21817fe350e546b',
		's2.b1.i1': '102566e11462e84f',
		's2.b1.i2': '83bc170018336efe',
		's2.b2': 'eb88a7323310e67e',
	},
};
