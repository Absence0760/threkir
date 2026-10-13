import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'invite-members-and-roles',
	title: 'Mitglieder einladen und Rollen vergeben',
	summary: 'Teile einen Einladungslink, genehmige Beitrittsanfragen und gib vertrauenswürdigen Mitgliedern die Rolle Admin, Eventorganisator oder Renndirektor.',
	sections: [
		{
			heading: 'Wie man beitritt',
			blocks: [
				{
					type: 'p',
					text: 'Wie jemand beitritt, hängt von der Beitrittsregel des Clubs ab, die du beim Erstellen gewählt hast und im Web mit **Club bearbeiten** ändern kannst.',
				},
				{
					type: 'list',
					items: [
						'**Jeder kann beitreten**: Man wählt auf der Club-Seite **Club beitreten** und ist sofort dabei.',
						'**Freigabe erforderlich**: Man wählt **Beitritt anfragen** und wartet in einer Warteschlange, bis ein Admin zustimmt.',
						'**Nur mit Einladung**: Man braucht einen Einladungslink von einem Admin.',
					],
				},
			],
		},
		{
			heading: 'Einen Einladungslink teilen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne deinen Club im Web. Ist der Club auf **Nur mit Einladung** gestellt, sehen Admins auf der Club-Seite einen Bereich **Einladungslink**.',
						'Wähle beim ersten Mal **Einladungslink erstellen** und dann **Kopieren**, um den Link in die Zwischenablage zu legen.',
						'Verschicke den Link, wie du möchtest. Wer ihn öffnet und sich anmeldet, tritt dem Club als Mitglied bei.',
					],
				},
				{
					type: 'p',
					text: 'Hat sich ein Link weiter verbreitet als gewollt, wähle **Erneuern**. Ein neuer Link wird erstellt, und der alte funktioniert sofort nicht mehr.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ein Einladungslink lässt Leute direkt herein: Er umgeht die Warteschlange für Freigaben, teile ihn also nur mit Personen, die du gern aufnimmst. Verlangt der Club die Bestätigung der Aktivitätsrisiken, fragt der Link sie ab, bevor er jemanden hereinlässt.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'In der Handy-App kann ein Mitglied auch unter **Sozial** im Tab **Clubs** auf **Mit Einladungscode beitreten** tippen und den ganzen Link oder nur den Code nach /clubs/join/ einfügen. Den Link in einem Browser auf dem Handy zu öffnen funktioniert ebenfalls.',
				},
			],
		},
		{
			heading: 'Beitrittsanfragen genehmigen oder ablehnen',
			blocks: [
				{
					type: 'p',
					text: 'Braucht der Club eine Freigabe, sehen Admins **Ausstehende Anfragen** mit einer Zahl daneben.',
				},
				{
					type: 'list',
					items: [
						'Wähle im Web bei jeder Anfrage **Genehmigen** oder **Ablehnen** oder **Alle genehmigen**, wenn mehrere warten. Vor dem Ablehnen wirst du um Bestätigung gebeten.',
						'Öffne in der Handy-App den Tab **Mitglieder** des Clubs und tippe bei jeder Anfrage auf **Genehmigen** oder **Ablehnen**.',
					],
				},
			],
		},
		{
			heading: 'Mitgliedern eine Rolle geben',
			blocks: [
				{
					type: 'p',
					text: 'Jeder Club hat einen **Inhaber**, die Person, die ihn erstellt hat. Andere können eine dieser Rollen haben:',
				},
				{
					type: 'list',
					items: [
						'**Admin**: ändert die Einstellungen des Clubs, verwaltet Mitglieder und ihre Rollen, leitet Events und Rennen und genehmigt Ergebnisse.',
						'**Eventorganisator**: erstellt, bearbeitet und löscht Events und fügt Teilnehmende hinzu, ohne Zugriff auf Club-Einstellungen oder Mitglieder.',
						'**Renndirektor**: stellt Rennen scharf, startet und beendet sie und genehmigt oder lehnt Ergebnisse ab.',
						'**Mitglied**: schreibt Antworten, gibt bei Events Rückmeldung zur Teilnahme und reicht eigene Rennergebnisse ein.',
					],
				},
				{
					type: 'steps',
					items: [
						'Öffne deinen Club im Web und wähle den Tab **Mitglieder**.',
						'Wähle im Rollenmenü neben einem Mitglied seine neue Rolle. Die Änderung wird sofort gespeichert.',
						'Um jemanden aus dem Club zu entfernen, nutze die Entfernen-Schaltfläche daneben und bestätige.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Rollen ändern und Mitglieder entfernen geht vorerst nur im Web. Der Tab **Mitglieder** der Handy-App zeigt die Mitgliederzahl und die ausstehenden Anfragen, nicht die vollständige Liste.',
				},
			],
		},
	],
	sources: {
		title: '7a795179c19e9ede',
		summary: '6bd8f063f9b47e9c',
		's0.heading': 'a0b11759509dec45',
		's0.b0': '6373b2a85a1609f6',
		's0.b1.i0': 'ee27e4b5847787d3',
		's0.b1.i1': 'b3ca923e10bea1a6',
		's0.b1.i2': '43f232607a69a9eb',
		's1.heading': 'ff3fad2f072540f7',
		's1.b0.i0': '53bc4c42c338a50b',
		's1.b0.i1': '527bae1b53082d53',
		's1.b0.i2': '7717031f30823ba7',
		's1.b1': '71a8c58fdf04e4c7',
		's1.b2': 'ac04b52b16128c47',
		's1.b3': '95001612b9e89408',
		's2.heading': 'ac0d31b6960aec87',
		's2.b0': '5e020c1365ade658',
		's2.b1.i0': '001fdb020367ef82',
		's2.b1.i1': '8a13349f6280affe',
		's3.heading': '5ae9577e9c45959a',
		's3.b0': '6b88528b0352a4ca',
		's3.b1.i0': '4a654fadcb92a4e9',
		's3.b1.i1': '4fb82402d20e5ae6',
		's3.b1.i2': '99c1319e71b4efe7',
		's3.b1.i3': 'd2c28cf99bce668b',
		's3.b2.i0': '8552b807ede6b519',
		's3.b2.i1': '12d66025f3fdd53b',
		's3.b2.i2': '2bc7dca0194195b4',
		's3.b3': '2dbf13356f8d50fe',
	},
};
