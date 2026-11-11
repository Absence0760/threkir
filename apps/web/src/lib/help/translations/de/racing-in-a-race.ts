import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'racing-in-a-race',
	title: 'Bei einem Live-Rennen mitlaufen',
	summary: 'Melde dich an, wähle deine Strecke, starte die Aufzeichnung vor der Startlinie und lass dein Handy oder deine Uhr deine Zeit von der Startlinie bis zur Ziellinie nehmen.',
	sections: [
		{
			heading: 'Mit welchen Geräten du mitlaufen kannst',
			blocks: [
				{
					type: 'list',
					items: [
						'Android-App: volle Unterstützung. Sie zeigt das Renn-Banner, sendet deine Live-Position und nimmt deine Zeit an der Start- und Ziellinie.',
						'iPhone-App: Sie läuft mit demselben Code wie Android, wurde aber noch nicht in einem echten Rennen auf einem iPhone getestet.',
						'Wear-OS-Uhr: volle Unterstützung am Handgelenk, einschließlich der Zeitnahme an den Linien. Anmelden und deine Strecke wählen musst du trotzdem im Web oder auf dem Handy.',
						'Apple Watch: nur frühe Unterstützung. Sie zeigt das Renn-Banner, sendet deine Position und meldet deine Zeit über dein iPhone, erkennt aber die Start- und Ziellinie nicht, hat also keinen automatischen Zieleinlauf, und wurde noch nicht in einem echten Rennen erprobt. Nimm dein Handy zur Sicherheit mit oder miss dein Ergebnis danach im Web aus deinem Track neu.',
						'Web: Damit meldest du dich an, wählst eine Strecke, siehst Ergebnisse und misst ein Ergebnis aus dem Track eines Laufs neu. Ein Browser kann keinen Lauf aufzeichnen.',
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
					text: 'Wenn der Veranstalter das Rennen scharf schaltet, zeigt der Lauf-Tab der Handy-App **Rennen bereit** mit „warten auf GO“. Die Wear-OS-Uhr zeigt „RENNEN BEREIT“ über ihrer Start-Taste. Wenn der Veranstalter GO gibt, wechselt die Anzeige zu **Rennen LIVE** („RENNEN LÄUFT“ auf der Uhr) mit der verstrichenen Zeit und „auf Start tippen“.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Dein Handy oder deine Uhr startet die Aufzeichnung nicht von selbst: Drück selbst auf Start, bevor du die Startlinie erreichst. Du kannst starten, während das Rennen **Rennen bereit** zeigt, oder sobald du **Rennen LIVE** siehst. Eine früh gestartete Aufzeichnung wird bei GO mit dem Rennen verknüpft, auf dem Handy und auf einer Wear-OS-Uhr.',
				},
				{
					type: 'p',
					text: 'Die Handy-App sucht nach Rennen, für die du **Bin dabei** gesagt hast und die innerhalb des nächsten Tages starten. Erscheint das Banner nur zögerlich, lass die App eine Minute lang im Lauf-Tab geöffnet.',
				},
			],
		},
		{
			heading: 'Die Startlinie überqueren',
			blocks: [
				{
					type: 'p',
					text: 'Hat deine Strecke eine Startlinie, zeigt der Laufbildschirm, wie weit sie entfernt ist, zum Beispiel „120 m bis zur Startlinie“. Lauf in Richtung der Strecke durch sie hindurch. Nach GO vibriert dann dein Handy oder deine Wear-OS-Uhr, sagt „Startlinie überquert, Zeitmessung läuft“, wenn Sprachansagen eingeschaltet sind, und deine Nettozeit läuft ab diesem Moment.',
				},
				{
					type: 'list',
					items: [
						'Bist du schon über die Startlinie hinaus, wenn GO ertönt? Dann ist GO selbst dein Start.',
						'Wenn du die Linie vor GO überquerst, etwa beim Aufwärmen, zählt das nicht. Nach GO zählt dein Start, sobald du etwa 50 m auf der Strecke zurückgelegt hast, ohne wieder über die Linie zurückzukommen.',
						'Erkennt dein Handy oder deine Uhr nie, dass du die Startlinie überquerst, läuft deine Nettozeit stattdessen ab dem Moment, in dem du auf Start gedrückt hast.',
					],
				},
			],
		},
		{
			heading: 'Automatischer Zieleinlauf',
			blocks: [
				{
					type: 'p',
					text: 'Im Ziel musst du nichts drücken. Hat deine Strecke eine Ziellinie, wertet dein Handy oder deine Wear-OS-Uhr deinen Zieleinlauf in dem Moment, in dem du in Richtung der Strecke durch sie hindurchläufst, sobald du genug von der Strecke zurückgelegt hast: 60 % ihrer Distanz seit dem Überqueren der Startlinie, oder 90 %, wenn kein Überqueren der Startlinie erkannt wurde. So bringt dich eine Rundstrecke, die dort startet, wo sie endet, nicht schon auf dem Hinweg ins Ziel.',
				},
				{
					type: 'p',
					text: 'Wenn du auf einem Weg neben der Ziellinie an ihr vorbeiläufst, zählt das nicht, weil du nie durch sie hindurchläufst. Deine Zeit wird in dem Moment genommen, in dem du die Linie überquert hast. Das Handy vibriert und zeigt „Im Ziel!“ mit deiner Bruttozeit.',
				},
				{
					type: 'p',
					text: 'Bei einer Strecke mit Zielpunkt, aber ohne Ziellinie gilt die ältere Regel: Du bist im Ziel, sobald du höchstens 30 m vom Ziel entfernt bist und 90 % der Strecke zurückgelegt hast, und die Zeit wird in dem Moment genommen, in dem du ihm am nächsten warst. Auf einer Strecke mit Ziellinie zählt dieser 30-m-Kreis nur, wenn du darin Stopp oder **Rennen beenden** drückst.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Es gibt keinen automatischen Zieleinlauf, wenn deine Strecke keine Distanz hat, weder eine Ziellinie noch einen Zielpunkt hat oder eine Route hat, die ihre eigene Ziellinie vor dem Ende überquert, wie es eine Strecke aus Runden tut. Nutze Stopp und dann **Rennen beenden**, wenn du die Linie überquerst.',
				},
			],
		},
		{
			heading: 'Nicht im Ziel? Fortsetzen',
			blocks: [
				{
					type: 'p',
					text: 'Ein Zieleinlauf über die Linie wird sofort gesendet, und deine Aufzeichnung pausiert. In den nächsten 60 Sekunden bietet der Laufbildschirm **Nicht im Ziel? Fortsetzen** an, auf dem Handy und auf einer Wear-OS-Uhr. Bist du noch nicht im Ziel, weil du die Linie etwa in einer Runde zu früh überquert hast, tippe darauf: Dein Ergebnis wird zurückgenommen, und die Aufzeichnung läuft weiter. Tust du nichts, stoppt die Aufzeichnung, und das Ergebnis bleibt bestehen.',
				},
				{
					type: 'p',
					text: 'Nachdem du einen Zieleinlauf rückgängig gemacht hast, beendest du den Rest des Rennens von Hand: Tippe auf Stopp und dann auf **Rennen beenden**, wenn du wirklich im Ziel bist. Startet die App vorher neu, beobachtet sie die Ziellinie wieder, zählt aber nie den Zieleinlauf, den du rückgängig gemacht hast.',
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
			heading: 'Bruttozeit, Nettozeit und später Start',
			blocks: [
				{
					type: 'list',
					items: [
						'**Bruttozeit** läuft ab dem Moment, in dem der Veranstalter GO gegeben hat, bis zu deinem Zieleinlauf. Nach ihr wirst du platziert.',
						'**Nettozeit** läuft ab dem Überqueren der Startlinie bis zu deinem Zieleinlauf. Wurde kein Überqueren der Startlinie erkannt, läuft sie ab dem Moment, in dem du auf Start gedrückt hast, oder ab GO, wenn du früher auf Start gedrückt hast. Sie ist nie länger als deine Bruttozeit.',
						'Startest du mehr als 5 Minuten nach GO oder ist deine erste Position mehr als 200 m vom Start der Strecke entfernt, zeigt die Handy-App einen Hinweis auf den späten Start, und eine Wear-OS-Uhr zeigt unter der Rennuhr dauerhaft **Später Start**. Deine Bruttozeit zählt trotzdem ab GO, sodass ein später Start sie länger macht als deine Nettozeit.',
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
	sources: {
		title: '3ce73ee9613bf595',
		summary: '8a84191c960f3189',
		's0.heading': 'ac0fdba8f9fafc40',
		's0.b0.i0': '5f9d1c45bcbbfb31',
		's0.b0.i1': 'c4096345432d33e6',
		's0.b0.i2': '547cdcc69e247581',
		's0.b0.i3': 'f068efe69456ba52',
		's0.b0.i4': '13822228d183e2b0',
		's1.heading': 'f00c55d7857a6dce',
		's1.b0.i0': '30eeadd878d7b098',
		's1.b0.i1': '525a552fd753b987',
		's1.b0.i2': '9efc1bb52d90e6ef',
		's1.b1': '55c32b3a7d7a241c',
		's2.heading': 'ed31d49e898938c8',
		's2.b0': 'f4ff1ecc36a2cf8e',
		's2.b1': 'b77e8bc9d60c9032',
		's2.b2': 'ddeff25fbc81b659',
		's3.heading': '3a0b0b0d9f43041c',
		's3.b0': '521195c2168d7fda',
		's3.b1.i0': '90b0261b0ce9c3f1',
		's3.b1.i1': 'a8d5dd7d6540cf62',
		's3.b1.i2': '8984cdb2a3694851',
		's4.heading': 'b1c0468dde456524',
		's4.b0': '900f305519a8032c',
		's4.b1': '32f9e651e83644d2',
		's4.b2': 'b39f1ce0d4a09d1a',
		's4.b3': '0e408636f1230c3b',
		's5.heading': 'bfa00064941be0cc',
		's5.b0': '86c65402c413b22d',
		's5.b1': 'a71d2963bd840180',
		's6.heading': '5df934589d491767',
		's6.b0': 'f1a6d8c09124a7d8',
		's6.b1.i0': '7a35b26309af9c5b',
		's6.b1.i1': 'f2cbc2dc9b04ff5b',
		's6.b1.i2': '630eba7ef0538b75',
		's6.b2': 'a0e378aecf393dda',
		's6.b3': 'b99b4c432279d3ea',
		's7.heading': '19cee1ff0ce4a9e3',
		's7.b0': 'b44459cc78b71aaf',
		's8.heading': 'b26ffa9d3d25af83',
		's8.b0.i0': '5aa5f4e57b72adfb',
		's8.b0.i1': '43b664e01ad5869b',
		's8.b0.i2': 'ce8974750a19dc0f',
		's8.b1': '1a0778a6029af8ae',
		's9.heading': '8cfcf517e30f6408',
		's9.b0': 'e103d457341fcf30',
	},
};
