import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'live-tracking-and-safety',
	title: 'Live-Tracking und Sicherheitskontakte',
	summary: 'Lass jemanden deinen Lauf live verfolgen und vertrauenswürdige Kontakte per E-Mail benachrichtigen, wenn du fertig bist, nichts mehr sendest oder nicht rechtzeitig zurück bist.',
	sections: [
		{
			heading: 'Einen Live-Link teilen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Melde dich in der Handy-App an. Ein Live-Link funktioniert nur, wenn du angemeldet bist.',
						'Tippe auf dem Laufbildschirm vor dem Start auf **Live-Link teilen** und sende ihn mit einer beliebigen App auf deinem Handy.',
						'Tippe auf **START**. Der Link wird live, sobald der Lauf beginnt.',
					],
				},
				{
					type: 'p',
					text: 'Wer den Link hat, kann ihn in einem Webbrowser öffnen und deine Position und Werte verfolgen, ganz ohne Konto. Datenschutzzonen gelten auch auf der Live-Karte.',
				},
				{
					type: 'p',
					text: 'Während du teilst, erscheint auf dem Aufzeichnungsbildschirm ein Abzeichen **Live**. Tippe darauf für **Link erneut teilen** oder **Teilen beenden** oder um unter **Nicht zurück bis …** eine Uhrzeit festzulegen.',
				},
				{
					type: 'p',
					text: 'Wenn der Lauf endet, wird der Link nicht mehr aktualisiert. Sind deine Läufe normalerweise nicht öffentlich, wirst du gefragt, ob du den gespeicherten Lauf für Personen mit dem Link **Öffentlich lassen** möchtest; andernfalls gilt wieder dein üblicher Datenschutz für Läufe.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Um jeden Lauf zu teilen, ohne daran denken zu müssen, schalte im Tab **Du** unter **Sicherheitskontakte** die Option **Automatisches Live-Teilen** ein. Sie gilt nur für dieses Handy, und der laufende Lauf kann von allen mit dem Link angesehen werden.',
				},
			],
		},
		{
			heading: 'Sicherheitskontakte hinzufügen',
			blocks: [
				{
					type: 'p',
					text: 'Ein Sicherheitskontakt ist eine Person, der du vertraust, etwa deine Partnerin oder dein Partner, jemand aus deinem Freundeskreis oder ein Familienmitglied. Diese Person wird per E-Mail benachrichtigt, wenn du einen Lauf beendest, auch einen privaten, damit sie weiß, dass du zurück bist.',
				},
				{
					type: 'steps',
					items: [
						'Öffne im Web [[route:/settings/safety|Sicherheit]] in den Einstellungen oder in der Handy-App **Sicherheitskontakte** im Tab **Du**.',
						'Gib die **E-Mail des Kontakts** ein. Du kannst auch ein **Telefon für SMS (optional)** im internationalen Format hinzufügen, etwa +447700900123.',
						'Wähle **Kontakt hinzufügen**. Die Person erhält eine E-Mail mit der Bitte um Bestätigung.',
						'Der Status des Kontakts lautet **Ausstehend — wartet auf Bestätigung**, bis die Person zustimmt, danach **Bestätigt**. Nur bestätigte Kontakte werden alarmiert.',
					],
				},
				{
					type: 'p',
					text: 'Wenn dich jemand als Kontakt hinzufügt, erscheint die Anfrage unter **Anfragen an dich**, wo du **Bestätigen** oder **Ablehnen** kannst. Später kannst du unter **Du bist Sicherheitskontakt** ändern, wie du alarmiert wirst, oder **Zurückziehen**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'E-Mail-Alarme werden immer gesendet. Für SMS muss der Kontakt beim Bestätigen zusätzlich zustimmen, und der SMS-Versand ist noch nicht überall eingeschaltet – verlass dich also nicht allein auf SMS.',
				},
			],
		},
		{
			heading: 'Alarme, wenn etwas nicht stimmt',
			blocks: [
				{
					type: 'p',
					text: 'Diese Alarme gelten nur für Läufe mit eingeschaltetem Live-Teilen, denn erst der Live-Link verrät uns, wo du bist. Jeder Kontakt erhält höchstens einen Alarm pro Lauf.',
				},
				{
					type: 'list',
					items: [
						'**Überfällig-Alarm**: Wähle im Web unter **Kontakte alarmieren nach Stille von** eine Zeit, in der App unter **Alarm nach Stille von**. Sendet dein Live-Lauf so lange nichts, erhalten deine bestätigten Kontakte deinen Live-Link per E-Mail. Die Einstellung steht auf **Aus**, bis du eine Zeit wählst.',
						'**Nicht zurück bis …**: Tippe während eines live geteilten Laufs auf das Abzeichen **Live** und wähle, wann du voraussichtlich fertig bist. Läuft der Lauf dann noch, werden deine Kontakte alarmiert. Die Zeit wird auf unserem Server gespeichert und zählt daher auch, wenn dein Handy ausgeht. Du kannst sie auch auf deiner eigenen Live-Seite im Web festlegen.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ein Verlust des Handysignals sieht genauso aus wie Funkstille, und ein Lauf, der ohne Signal endet, kann trotzdem einen Alarm auslösen, bis er hochgeladen ist. Die E-Mail weist deine Kontakte darauf hin, dass ein Signalverlust eine mögliche Ursache ist.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ein automatischer Alarm an deine Kontakte, wenn du deine geplante Route verlässt, ist gebaut, aber noch nicht eingeschaltet. Bis dahin bleibt die Einstellung **Routen-Warnung** ausgeblendet.',
				},
			],
		},
		{
			heading: 'Warnungen beim Verlassen der Route',
			blocks: [
				{
					type: 'p',
					text: 'Wenn du einer gespeicherten Route folgst, warnt dich der Laufbildschirm, sobald du von ihr abweichst, zeigt an, wie weit du entfernt bist, und kann es bei eingeschalteten Sprachansagen auch laut sagen. Diese Warnung ist nur für dich; sie benachrichtigt niemanden.',
				},
			],
		},
	],
	sources: {
		title: 'cee4d0a20867ed19',
		summary: '45984309810e4f6b',
		's0.heading': 'dc5c5a630221dbbc',
		's0.b0.i0': 'f62182995094fa0a',
		's0.b0.i1': '5df8617dc302468a',
		's0.b0.i2': 'fd23a78c3f8edbbd',
		's0.b1': 'f45b4fcfccc4fb7e',
		's0.b2': '7845c9dd61f6fcbd',
		's0.b3': '21b6940abd1d8d09',
		's0.b4': '822ce03c51253ce8',
		's1.heading': '7fe0f3d3bca83ca6',
		's1.b0': '8983069471135762',
		's1.b1.i0': '6675420e0916edbb',
		's1.b1.i1': '8ad53d18b45a91df',
		's1.b1.i2': '921f48df34ed7a60',
		's1.b1.i3': 'fb0e10c56d0013a1',
		's1.b2': 'd5654527a9969a6c',
		's1.b3': '38a6734637422840',
		's2.heading': '6494ef66d8a744ee',
		's2.b0': '3076b2df5cf96aca',
		's2.b1.i0': 'd1a279384aa709ce',
		's2.b1.i1': '43b13b285ccc1278',
		's2.b2': '968742a451f6aa8a',
		's2.b3': '0694224872716044',
		's3.heading': '4799e1fbd28720f2',
		's3.b0': '2557edbaef77cc2c',
	},
};
