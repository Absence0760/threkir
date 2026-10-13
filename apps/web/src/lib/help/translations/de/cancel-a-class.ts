import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'cancel-a-class',
	source: '8ee15ec25324129c',
	title: 'Einen Kurs absagen und allen Zahlenden ihr Geld erstatten',
	summary: 'Sag einen Termin eines wiederkehrenden Kurses ab; alle, die dafür bezahlt haben, bekommen automatisch den vollen Betrag erstattet, mit stündlichem Neuversuch und „Jetzt erstatten“ als Ausweg.',
	sections: [
		{
			heading: 'Bevor du loslegst',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Bezahlte Kurse sind noch nicht live: Dafür muss das Stripe-Konto des Veranstalters verbunden und das Bezahlsystem der Plattform eingeschaltet sein. Sind Zahlungen nicht verfügbar, wenn du einen Termin mit bezahlten Anmeldungen absagen willst, siehst du **Für diesen Termin gibt es bezahlte Anmeldungen, und Zahlungen sind gerade nicht verfügbar. Deshalb kann er noch nicht abgesagt werden. Es wurde nichts geändert.** Der Kurs bleibt bestehen, damit niemand auf einer Zahlung für einen Kurs sitzen bleibt, der nicht stattfindet.',
				},
				{
					type: 'p',
					text: 'Absagen können Admins und Eventorganisatoren des Clubs, und zwar im Web. Kostenlose Kurse sagst du genauso ab, nur ohne Erstattungen.',
				},
			],
		},
		{
			heading: 'Einen Termin absagen',
			blocks: [
				{
					type: 'steps',
					items: [
						'Öffne den Kurs im Web. Wiederholt er sich, wähle mit **Termin auswählen** das Datum, das du absagst.',
						'Drücke **Diesen Termin absagen**.',
						'Der Dialog erklärt, dass nur dieser Termin abgesagt wird und der Rest der Serie unberührt bleibt. Bei einem bezahlten Kurs ergänzt er: **Alle Angemeldeten für diesen Termin bekommen den vollen Betrag erstattet, unabhängig von den Erstattungsbedingungen.**',
						'Gib optional einen **Grund (optional)** an und drücke dann zur Bestätigung erneut **Diesen Termin absagen** oder **Beibehalten**, um abzubrechen.',
					],
				},
				{
					type: 'p',
					text: 'Danach siehst du, wie viele Personen eine Erstattung bekommen, zum Beispiel *Termin abgesagt. 8 angemeldete Personen bekommen den vollen Betrag erstattet.* Wer gerade mitten im Bezahlvorgang war, bekommt seinen reservierten Platz freigegeben und wird nicht belastet. Niemand von der Warteliste rückt in einen abgesagten Kurs nach.',
				},
			],
		},
		{
			heading: 'Was deine Teilnehmenden erfahren',
			blocks: [
				{
					type: 'p',
					text: 'Alle, die für diesen Termin geantwortet haben (zugesagt, vielleicht oder auf der Warteliste), werden benachrichtigt. Wer bezahlt hat, bekommt eine Benachrichtigung wie *Ein Termin von „Tuesday Reformer“ wurde abgesagt – deine Zahlung wird erstattet*, und derselbe Text geht per E-Mail oder Push an alle, die diese erhalten. Es heißt *wird* erstattet, weil die Erstattung in diesem Moment gestartet wird und ein paar Tage brauchen kann, bis sie bei der Bank ankommt.',
				},
			],
		},
		{
			heading: 'Wenn eine Erstattung fehlschlägt',
			blocks: [
				{
					type: 'p',
					text: 'Der Termin bleibt abgesagt, auch wenn Stripe eine Erstattung ablehnt. Du siehst eine Meldung, wie viele Erstattungen nicht gestartet werden konnten, und die Kursseite bekommt eine Karte **Erstattungen für abgesagte Termine**, die pro abgesagtem Termin zeigt, wer noch nichts erstattet bekommen hat, welche Erstattungen laufen und welche die Bank zurückgeschickt hat.',
				},
				{
					type: 'list',
					items: [
						'Die App versucht jede noch offene Erstattung für einen abgesagten Kurs automatisch einmal pro Stunde erneut.',
						'Du musst nicht warten: Drücke **Jetzt erstatten** neben dem Termin, um es sofort erneut zu versuchen. Dabei bekommt niemand doppelt erstattet.',
						'Eine Erstattung, die die Bank zurückschickt, lässt sich so nicht erneut versuchen; die Person bekommt das Geld auf anderem Weg zurück.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Erstatte nicht von Hand über ein Stripe-Dashboard. Eine dort ausgelöste Erstattung kann die Rückbuchung deiner Auszahlung und der Plattformgebühr überspringen, und die App erstattet dann womöglich den Rest noch obendrauf. Nutze stattdessen **Jetzt erstatten**.',
				},
			],
		},
		{
			heading: 'Einmalige Kurse und ganze Serien',
			blocks: [
				{
					type: 'p',
					text: '**Diesen Termin absagen** gibt es nur bei einem wiederkehrenden Kurs. Es gibt keinen einzelnen Button, um eine ganze Serie abzusagen: Sag jeden anstehenden Termin ab, der Anmeldungen hat.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: '**Veranstaltung löschen** ist keine Absage. Es entfernt das Event mit allen Terminen und erstattet niemandem, der bezahlt hat. Lösche keinen bezahlten Kurs, der noch Anmeldungen hat.',
				},
				{
					type: 'p',
					text: 'Doch anders entschieden? **Diesen Termin wiederherstellen** setzt einen abgesagten Termin wieder in den Kalender, aber bereits ausgeführte Erstattungen werden nicht rückgängig gemacht – die Leute müssen sich also neu anmelden.',
				},
			],
		},
	],
};
