import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'recurring-events',
	title: 'Ein wiederkehrendes Club-Event einrichten',
	summary: 'Mach aus einem Club-Event eine wöchentliche, zweiwöchentliche oder monatliche Serie, sag für einen einzelnen Termin zu und sag einen Termin ab, ohne den Rest anzutasten.',
	sections: [
		{
			heading: 'Serie erstellen',
			blocks: [
				{
					type: 'p',
					text: 'Club-Inhaber, Admins und Eventorganisatoren können Events erstellen. Ein wiederkehrendes Event ist ein einziges Event, das sich wiederholt – alles, was du ausfüllst, gilt also für jeden Termin.',
				},
				{
					type: 'steps',
					items: [
						'Öffne deinen Club im Web und wähle **Neues Event**.',
						'Fülle **Titel**, **Startzeit** und die übrigen Angaben wie bei einem einmaligen Event aus. Die gewählte Startzeit ist der erste Termin der Serie.',
						'Wähle unter **Wiederholung** statt **Einmalig** die Option **Wöchentlich**, **Alle 2 Wochen** oder **Monatlich**.',
						'Wähle bei einer wöchentlichen oder zweiwöchentlichen Serie die Wochentage unter **An diesen Tagen:**. Eine monatliche Serie wiederholt sich am selben Tag des Monats wie das Startdatum.',
						'Leg fest, wann die Serie endet: Setze **Endet am** auf ein Datum, **Endet nach** auf eine Anzahl von Terminen oder beides – was zuerst eintritt, gilt. Bleiben beide leer, wiederholt sie sich unbegrenzt.',
						'Wähle **Event erstellen**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Das Wiederholungsmuster lässt sich nur beim Erstellen des Events wählen. **Veranstaltung bearbeiten** ändert Titel, Uhrzeit, Treffpunkt und die übrigen Angaben für die ganze Serie, aber nicht, wie oft sie sich wiederholt.',
				},
				{
					type: 'p',
					text: 'Tippe in der Handy-App im Tab **Events** des Clubs auf **Event erstellen** und wähle unter **Wiederholung** die Option **Wöchentlich**, **Zweiwöchentlich** oder **Monatlich**. Die App wiederholt das Event am Wochentag des Startdatums und kennt weder ein Enddatum noch eine Anzahl von Terminen – nutze also das Web, wenn die Serie enden soll.',
				},
			],
		},
		{
			heading: 'Für einen Termin zusagen',
			blocks: [
				{
					type: 'p',
					text: 'Jeder Termin einer Serie hat eigene Zusagen, eine eigene Teilnehmerliste, eine eigene Kapazität und eigene Ergebnisse.',
				},
				{
					type: 'steps',
					items: [
						'Öffne das Event und wähle mit **Termin auswählen** das Datum. Die nächsten Termine werden angezeigt, und **Alle anzeigen** klappt alle anstehenden Termine des nächsten Jahres auf.',
						'Wähle für diesen Termin **Ich bin dabei**, **Vielleicht** oder **Kann nicht**.',
					],
				},
				{
					type: 'p',
					text: 'Um die Termine in deinen eigenen Kalender zu übernehmen, wähle **In Kalender eintragen**. Bei einer Serie kannst du **Diesen Termin eintragen** für einen Termin oder **Ganze Serie eintragen** für alle Termine wählen.',
				},
			],
		},
		{
			heading: 'Einen Termin absagen',
			blocks: [
				{
					type: 'p',
					text: 'Wenn ein Termin nicht stattfinden kann, sag nur diesen ab und lass den Rest der Serie, wie er ist.',
				},
				{
					type: 'steps',
					items: [
						'Öffne das Event im Web und wähle den Termin, den du absagen musst.',
						'Wähle **Diesen Termin absagen**.',
						'Gib einen **Grund (optional)** an, etwa eine überflutete Strecke oder einen Feiertag, und bestätige. Wähle **Beibehalten**, falls du es dir anders überlegst.',
					],
				},
				{
					type: 'p',
					text: 'Alle, die für diesen Termin geantwortet haben – ob zugesagt, vielleicht oder auf der Warteliste –, bekommen eine Benachrichtigung. Der Termin zeigt **Dieser Termin wurde abgesagt.** und niemand kann mehr dafür zusagen. Um ihn zurückzuholen, öffne den Termin und wähle **Diesen Termin wiederherstellen**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Termine absagen und wiederherstellen geht nur im Web. **Veranstaltung löschen** entfernt jeden Termin der Serie, nicht nur einen.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Ist das Event ein bezahlter Kurs, bekommen beim Absagen eines Termins alle dafür Angemeldeten den vollen Betrag erstattet. Siehe [[guide:host-a-paid-yoga-class|Einen bezahlten Yogakurs anbieten]].',
				},
			],
		},
	],
	sources: {
		title: 'e613c3be8d106d58',
		summary: '16e60fe00d2cd802',
		's0.heading': '718e1069f51a2cb4',
		's0.b0': '3db51494677d6358',
		's0.b1.i0': '7b361a4f9398e384',
		's0.b1.i1': '17734b394312df43',
		's0.b1.i2': '0f73dbb856a7fa67',
		's0.b1.i3': 'a002823ae62a3df3',
		's0.b1.i4': 'e54a7bd9afd1d160',
		's0.b1.i5': 'ec48c553acdf742f',
		's0.b2': 'df7167c739a9ea9e',
		's0.b3': 'c40bdc990b5425db',
		's1.heading': 'd0f06618475ee3d1',
		's1.b0': 'fb3d5e80f695a45d',
		's1.b1.i0': '11bf9a8e15037b7c',
		's1.b1.i1': 'e208d82edea8262f',
		's1.b2': 'c2477719db027ba7',
		's2.heading': 'f95356ca142cc32c',
		's2.b0': '2836a3e020560d5f',
		's2.b1.i0': 'db8f532e330056ff',
		's2.b1.i1': '0c4ddfc33914c615',
		's2.b1.i2': 'fa7eaa32d4fdc37a',
		's2.b2': 'b34bc386e0fc3cb4',
		's2.b3': 'c1fb4f63833b6418',
		's2.b4': 'dfb7d75cf658eb0a',
	},
};
