import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'drive-a-course',
	title: "Parcourir un tracé de course en voiture avant le jour J",
	summary: "Ouvrez un parcours public dans votre appli de cartes, voyez les tronçons qu'elle ne peut pas suivre et laissez l'appli mobile lire les notes du parcours à voix haute pendant que vous conduisez.",
	sections: [
		{
			heading: "Ce que fait cette fonction",
			blocks: [
				{ type: 'p', text: "Sur un itinéraire public ou une course au parcours public, **Parcourir le tracé en voiture** découpe le parcours en étapes que Google Maps, Plans d'Apple ou Waze peuvent suivre. Votre appli de cartes vous guide, y compris sur CarPlay et Android Auto." },
				{
					type: 'list',
					items: [
						"Google Maps accepte plusieurs arrêts par étape. Plans d'Apple et Waze n'acceptent qu'une destination à la fois, vous ouvrez donc chaque étape l'une après l'autre.",
						"Les parcours de course empruntent des chemins, des ponts et des routes fermées. La liste sous les étapes indique les tronçons que l'appli de cartes ne peut pas suivre, pour que vous sachiez quelles parties vous ne verrez pas.",
						"L'itinéraire de l'appli de cartes n'est qu'indicatif. Les notes suivent le vrai parcours.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Cette fonction est activée progressivement. Si un parcours public n'affiche pas **Parcourir le tracé en voiture**, elle n'est pas encore disponible pour vous." },
			],
		},
		{
			heading: "Ouvrir un parcours dans une appli de cartes",
			blocks: [
				{
					type: 'steps',
					items: [
						"Ouvrez l'itinéraire ou la course et sélectionnez **Parcourir le tracé en voiture**.",
						"Choisissez votre appli de cartes, puis sélectionnez **Aller au départ**.",
						"Au départ, ouvrez l'étape 1. Quand une étape se termine, ouvrez la suivante.",
					],
				},
				{ type: 'p', text: "La page web liste aussi chaque note du parcours avec sa distance, et vous pouvez imprimer la liste pour un passager." },
			],
		},
		{
			heading: "Écouter les notes du parcours sur le téléphone",
			blocks: [
				{
					type: 'steps',
					items: [
						"Dans l'appli mobile, ouvrez l'itinéraire ou la course et touchez **Parcourir le tracé en voiture**.",
						"Lisez l'avertissement de sécurité et touchez **J'ai compris**. Il n'apparaît qu'une fois par téléphone.",
						"Touchez **Lancer les notes vocales**, passez à votre appli de cartes et verrouillez le téléphone.",
					],
				},
				{ type: 'p', text: "Chaque ravitaillement, barrière horaire, montée, danger et note est lu environ 15 secondes avant d'y arriver, puis de nouveau quand vous y êtes. Si vous rejoignez le parcours en cours de route, les notes commencent là où vous êtes. Elles s'arrêtent à l'arrivée, ou après 10 minutes hors du parcours. Touchez **Arrêter** pour les arrêter plus tôt." },
				{ type: 'note', tone: 'caution', text: "Utilisez-la avec un passager ou un téléphone fixé, et ne touchez pas le téléphone en conduisant. Respectez le code de la route et la signalisation, et n'oubliez pas que les routes du parcours peuvent être fermées le jour de la course." },
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
