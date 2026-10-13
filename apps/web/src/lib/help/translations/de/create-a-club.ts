import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'create-a-club',
	source: 'eb2c9f65431381b4',
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
};
