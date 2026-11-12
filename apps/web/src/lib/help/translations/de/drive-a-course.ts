import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'drive-a-course',
	title: "Eine Rennstrecke vor dem Renntag abfahren",
	summary: "Öffne eine öffentliche Strecke in deiner Karten-App, sieh, welchen Abschnitten sie nicht folgen kann, und lass dir die Streckenhinweise während der Fahrt von der Handy-App vorlesen.",
	sections: [
		{
			heading: "Was es macht",
			blocks: [
				{ type: 'p', text: "Auf einer öffentlichen Route oder einem Rennen mit öffentlicher Strecke teilt **Strecke abfahren** die Strecke in Etappen auf, denen Google Maps, Apple Karten oder Waze folgen können. Die Karten-App übernimmt die Navigation, auch über CarPlay und Android Auto." },
				{
					type: 'list',
					items: [
						"Google Maps nimmt mehrere Zwischenziele pro Etappe. Apple Karten und Waze nehmen jeweils nur ein Ziel, deshalb öffnest du die Etappen nacheinander.",
						"Rennstrecken nutzen Wege, Brücken und gesperrte Straßen. Die Liste unter den Etappen zeigt die Abschnitte, denen die Karten-App nicht folgen kann, damit du weißt, welche Teile du nicht siehst.",
						"Die Route der Karten-App dient nur zur Orientierung. Die Streckenhinweise folgen der echten Strecke.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Strecke abfahren wird schrittweise freigeschaltet. Wenn eine öffentliche Strecke **Strecke abfahren** nicht anzeigt, ist es für dich noch nicht verfügbar." },
			],
		},
		{
			heading: "Eine Strecke in der Karten-App öffnen",
			blocks: [
				{
					type: 'steps',
					items: [
						"Öffne die Route oder das Rennen und wähle **Strecke abfahren**.",
						"Wähle deine Karten-App und dann **Zum Start fahren**.",
						"Öffne am Start Etappe 1. Wenn eine Etappe endet, öffne die nächste.",
					],
				},
				{ type: 'p', text: "Die Webseite listet außerdem jeden Streckenhinweis mit seiner Distanz auf, und du kannst die Liste für einen Beifahrer ausdrucken." },
			],
		},
		{
			heading: "Die Streckenhinweise auf dem Handy hören",
			blocks: [
				{
					type: 'steps',
					items: [
						"Öffne in der Handy-App die Route oder das Rennen und tippe auf **Strecke abfahren**.",
						"Lies den Sicherheitshinweis und tippe auf **Verstanden**. Er erscheint auf jedem Handy nur einmal.",
						"Tippe auf **Gesprochene Hinweise starten**, wechsle dann zu deiner Karten-App und sperre das Handy.",
					],
				},
				{ type: 'p', text: "Jede Verpflegungsstation, jeder Zielschluss, jeder Anstieg, jede Gefahrenstelle und jeder Hinweis wird etwa 15 Sekunden vorher vorgelesen und noch einmal, wenn du dort bist. Steigst du unterwegs ein, beginnen die Hinweise dort, wo du bist. Sie enden im Ziel oder nach 10 Minuten abseits der Strecke. Tippe auf **Stopp**, um sie früher zu beenden." },
				{ type: 'note', tone: 'caution', text: "Nutze es mit Beifahrer oder fest montiertem Handy und bediene das Handy nicht während der Fahrt. Beachte Verkehrsregeln und Schilder, und denk daran, dass Straßen der Strecke am Renntag gesperrt sein können." },
			],
		},
	],
	sources: {
		"title": "bbb89d013c30ae16",
		"summary": "48a420988cbd14e8",
		"s0.heading": "c74ea9dc9cd25b58",
		"s0.b0": "0c0cd5387f11ea68",
		"s0.b1.i0": "f99832ea6336c2e7",
		"s0.b1.i1": "f1890d3bd7eb5850",
		"s0.b1.i2": "2a2afee7d8920207",
		"s0.b2": "7d8297dee5795cc5",
		"s1.heading": "bcc63fa1329139a9",
		"s1.b0.i0": "14946890d3f8e349",
		"s1.b0.i1": "d191e63d2defd3a9",
		"s1.b0.i2": "886b24e27ccf472f",
		"s1.b1": "96f5e8e63b56c989",
		"s2.heading": "5d546a4fc1ae50a1",
		"s2.b0.i0": "c555d1adaded1b5f",
		"s2.b0.i1": "72929bf136e6a2eb",
		"s2.b0.i2": "888f501170932dde",
		"s2.b1": "d5bf7e3b65385652",
		"s2.b2": "86d1be053314ad10"
	},
};
