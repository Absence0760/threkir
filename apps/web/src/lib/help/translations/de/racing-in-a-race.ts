import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'racing-in-a-race',
	source: '92b29a6c8a21703a',
	title: 'Bei einem Live-Rennen mitlaufen',
	summary: 'Melde dich an, wähle deine Strecke, starte die Aufzeichnung an der Startlinie oder nach LOS und lass dein Handy oder deine Uhr deine Zeit an der Ziellinie nehmen.',
	sections: [
		{
			heading: 'Mit welchen Geräten du mitlaufen kannst',
			blocks: [
				{
					type: 'list',
					items: [
						'Android-App: volle Unterstützung. Sie zeigt das Renn-Banner, sendet deine Live-Position und wertet deinen Zieleinlauf automatisch.',
						'iPhone-App: Sie läuft mit demselben Code wie Android, wurde aber noch nicht in einem echten Rennen auf einem iPhone getestet.',
						'Wear-OS-Uhr: volle Unterstützung am Handgelenk, einschließlich des automatischen Zieleinlaufs. Anmelden und deine Strecke wählen musst du trotzdem im Web oder auf dem Handy.',
						'Apple Watch: nur frühe Unterstützung. Sie zeigt das Renn-Banner, sendet deine Position und meldet deine Zeit über dein iPhone, hat aber keinen automatischen Zieleinlauf und wurde noch nicht in einem echten Rennen erprobt. Nimm dein Handy zur Sicherheit mit.',
						'Web: Damit meldest du dich an, wählst eine Strecke und siehst Ergebnisse. Ein Browser kann keinen Lauf aufzeichnen.',
					],
				},
			],
		},
		{
			heading: 'Anmelden und Strecke wählen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne das Renn-Event.',
						'Gibt es mehr als eine Strecke, wähle im Web deine unter **Deine Strecke**. In der Handy-App wirst du mit **Wähle deine Strecke** zur Auswahl aufgefordert, wenn du auf **Bin dabei** tippst.',
						'Tippe auf **Ich bin dabei**. Nur eine Anmeldung mit **Ich bin dabei** erhält Rennbenachrichtigungen auf deinem Gerät; **Vielleicht** nicht.',
					],
				},
				{
					type: 'p',
					text: 'Meinung geändert? Wähle im Web unter **Deine Strecke** eine andere Strecke (du siehst dann „Strecke aktualisiert.“). Tippe in der Handy-App auf **Strecke ändern**. Leg dich auf deine Strecke fest, bevor du die Aufzeichnung startest: Dein Handy oder deine Uhr liest sie beim Start deiner Rennaufzeichnung aus, und dein Ergebnis landet in der Liste dieser Strecke.',
				},
			],
		},
		{
			heading: 'Rennen bereit und Rennen LIVE',
			blocks: [
				{
					type: 'p',
					text: 'Wenn der Veranstalter das Rennen scharfstellt, zeigt der Lauf-Tab der Handy-App **Rennen bereit** mit „warten auf START“. Die Wear-OS-Uhr zeigt „RENNEN BEREIT“ über ihrer Start-Taste. Wenn der Veranstalter LOS gibt, wechselt die Anzeige zu **Rennen LIVE** („RENNEN LÄUFT“ auf der Uhr) mit der verstrichenen Zeit und „auf Start tippen“.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Dein Handy oder deine Uhr startet die Aufzeichnung nicht von selbst: Drück selbst auf Start. Du kannst an der Startlinie starten, während das Rennen **Rennen bereit** zeigt, oder sobald du **Rennen LIVE** siehst. Eine früh gestartete Aufzeichnung wird bei LOS mit dem Rennen verknüpft, auf dem Handy und auf einer Wear-OS-Uhr, und deine Netto-Zeit zählt dann ab LOS statt ab dem Moment, in dem du auf Start gedrückt hast.',
				},
				{
					type: 'p',
					text: 'Die Handy-App sucht nach Rennen, für die du **Bin dabei** gesagt hast und die innerhalb des nächsten Tages starten. Erscheint das Banner nur zögerlich, lass die App eine Minute lang im Lauf-Tab geöffnet.',
				},
			],
		},
		{
			heading: 'Automatischer Zieleinlauf',
			blocks: [
				{
					type: 'p',
					text: 'Im Ziel musst du nichts drücken. Dein Handy oder deine Wear-OS-Uhr wertet deinen Zieleinlauf, wenn beides zutrifft:',
				},
				{
					type: 'list',
					items: [
						'du bist höchstens 30 m von der Ziellinie entfernt, und',
						'du hast mindestens 90 % der Distanz deiner Strecke zurückgelegt.',
					],
				},
				{
					type: 'p',
					text: 'Deine Zeit wird in dem Moment genommen, in dem du dem Ziel am nächsten warst, nicht im ersten Moment innerhalb von 30 m. Die 90-%-Regel verhindert, dass dich eine Rundstrecke, die dort startet, wo sie endet, schon in der ersten Sekunde ins Ziel bringt. Das Handy zeigt „Im Ziel!“ mit deiner Brutto-Zeit, und deine Aufzeichnung stoppt.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Hat deine Strecke keine Route oder keine Distanz, gibt es keinen automatischen Zieleinlauf. Nutze Stopp und dann **Rennen beenden**, wenn du die Linie überquerst.',
				},
			],
		},
		{
			heading: 'Anhalten während des Rennens',
			blocks: [
				{
					type: 'p',
					text: 'Während eines Live-Rennens beendet Stopp dein Rennen nicht. Es pausiert deine Aufzeichnung und zeigt **Rennen pausiert**. Die Rennuhr läuft weiter.',
				},
				{
					type: 'list',
					items: [
						'**Rennen fortsetzen** setzt die Aufzeichnung fort.',
						'**Rennen beenden** beendet dein Rennen sofort. Hast du mindestens 90 % der Strecke zurückgelegt, ist das ein manueller Zieleinlauf in diesem Moment.',
						'Unter 90 % heißt die Schaltfläche **Als DNF beenden**, und das Beenden erfasst ein DNF.',
					],
				},
				{
					type: 'p',
					text: 'Auf einer Wear-OS-Uhr bietet der Pausenbildschirm „Los“ zum Fortsetzen, und zum Beenden hältst du **Ziel** gedrückt.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Beendest du vor 90 % der Strecke, wird ein DNF erfasst. Wenn du nur angehalten hast, um einen Schnürsenkel zu binden, wähle **Rennen fortsetzen**.',
				},
			],
		},
		{
			heading: 'Kein Signal im Ziel',
			blocks: [
				{
					type: 'p',
					text: 'Im Zielbereich ist das Signal oft schlecht. Dein Handy und deine Wear-OS-Uhr speichern dein Ergebnis zuerst und senden es, sobald sie wieder verbunden sind, sodass es nicht verloren geht. Es muss uns innerhalb von 24 Stunden erreichen, nachdem der Veranstalter das Rennen beendet hat. Melde dich nicht von der App ab, bevor es gesendet wurde.',
				},
			],
		},
		{
			heading: 'Brutto-Zeit, Netto-Zeit und später Start',
			blocks: [
				{
					type: 'list',
					items: [
						'**Brutto-Zeit** läuft ab dem Moment, in dem der Veranstalter LOS gegeben hat, bis zu deinem Zieleinlauf. Nach ihr wirst du platziert.',
						'**Netto-Zeit** läuft ab dem Moment, in dem du auf Start gedrückt hast, bis zu deinem Zieleinlauf, einschließlich aller Pausen. Hast du vor LOS auf Start gedrückt, läuft sie ab LOS, sodass sie nie länger als deine Brutto-Zeit ist.',
						'Startest du mehr als 5 Minuten nach LOS oder ist deine erste Position mehr als 200 m vom Start der Strecke entfernt, zeigt die Handy-App einen Hinweis auf den späten Start. Deine Brutto-Zeit zählt trotzdem ab LOS, sodass ein später Start sie länger macht als deine Netto-Zeit.',
					],
				},
				{
					type: 'p',
					text: 'Mehr zum Lesen der Liste findest du in [[guide:race-results-explained|Rennergebnisse erklärt]].',
				},
			],
		},
		{
			heading: 'Wenn der Veranstalter das Rennen vorher beendet',
			blocks: [
				{
					type: 'p',
					text: 'Beendet der Veranstalter das Rennen, bevor du im Ziel bist, sagt dir dein Handy Bescheid, und deine Uhr zeigt „Rennen beendet“. Dein Lauf wird als normaler Lauf weiter aufgezeichnet, aber dein Gerät sendet kein Rennergebnis. Hattest du bereits eine Live-Position gesendet, wirst du im Rennen als DNF markiert.',
				},
			],
		},
	],
};
