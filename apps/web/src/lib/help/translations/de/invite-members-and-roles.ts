import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'invite-members-and-roles',
	source: '1140e414e73d9132',
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
};
