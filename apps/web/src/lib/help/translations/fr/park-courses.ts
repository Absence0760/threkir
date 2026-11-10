import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'park-courses',
	title: "Parcours des parcs : points de contrôle, saisons et classements",
	summary: "Comment un parcours de parc chronomètre votre sortie, pourquoi chaque point de contrôle compte, quand commence une saison et comment se classent Plus rapides et Le plus de passages.",
	sections: [
		{
			heading: "Qu'est-ce qu'un parcours de parc",
			blocks: [
				{ type: 'p', text: "Un parcours de parc est un parcours de contre-la-montre fixe sur un sentier d'un parc d'État ou d'un parc national. Il n'y a ni organisateur ni jour de course : courez-le quand le parc est ouvert, et une sortie qui couvre tout le parcours est chronométrée. Retrouvez-les sous **À courir quand vous voulez** dans [[route:/races|Épreuves et parcours]], les plus proches d'abord dès que vous indiquez un lieu, ou parcourez-les tous dans [[route:/parks|Parcours des parcs]]." },
				{
					type: 'list',
					items: [
						"C'est un contre-la-montre, pas une course. Le sentier reste ouvert à tous et personne ne l'encadre : respectez le règlement du parc et cédez le passage aux autres usagers du sentier.",
						"Chaque page de parcours indique la distance, le dénivelé positif, la forme, le revêtement et la difficulté, l'origine du tracé et si le parcours est ouvert.",
						"Sélectionnez **Suivre ce parcours** pour suivre le parcours comme un itinéraire. Cette option n'est pas proposée tant que le parcours est fermé.",
						"La rubrique **Description du parcours** de la page du parcours indique où se garer et chaque changement de direction dans l'ordre, par nom de sentier, avec les ponts, les gués, les changements de revêtement et les montées. Elle est rédigée à partir des données cartographiques ; tant que personne ne l'a vérifiée sur place, c'est indiqué au-dessus de la liste. La même description figure dans le fichier GPX du parcours.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Un parcours fermé garde ses temps et ses classements, mais merci de ne pas le courir avant sa réouverture. La page indique quand son statut a été vérifié pour la dernière fois." },
			],
		},
		{
			heading: "Points de contrôle : pourquoi les raccourcis ne comptent jamais",
			blocks: [
				{ type: 'p', text: "En plus du départ et de l'arrivée, un parcours peut avoir des points de contrôle en chemin. Votre sortie n'est chronométrée que si elle passe par chaque point de contrôle, dans l'ordre, entre le départ et l'arrivée. Une sortie qui coupe un virage, saute un lacet ou traverse par le milieu manque un point de contrôle et n'obtient pas de temps." },
				{ type: 'p', text: "Restez sur le sentier balisé. Couper un sentier l'abîme, et les parcs le considèrent comme une infraction à leur règlement." },
			],
		},
		{
			heading: "Les saisons suivent l'heure du parc",
			blocks: [
				{ type: 'p', text: "Une saison est une année civile dans le fuseau horaire du parc, pas le vôtre. Les classements repartent à zéro à minuit le 1er janvier là où se trouve le parc." },
				{ type: 'p', text: "Par exemple, une sortie qui démarre à 22 h le 31 décembre dans un parc de Virginie compte pour cette année-là, même si votre téléphone est réglé sur un fuseau où l'on est déjà le 1er janvier." },
			],
		},
		{
			heading: "Le classement Plus rapides",
			blocks: [
				{
					type: 'list',
					items: [
						"**Plus rapides** classe chaque coureur selon son meilleur temps sur le parcours. Vous apparaissez une seule fois, avec votre meilleure sortie.",
						"Il affiche cette année par défaut. Sélectionnez **Depuis toujours** pour les meilleurs temps de tous les temps.",
						"Filtrez par genre ou par tranche d'âge. Le filtre d'âge n'inclut que les coureurs qui ont accepté de partager leurs données de santé, il peut donc être plus court que le classement complet.",
					],
				},
			],
		},
		{
			heading: "Le classement Le plus de passages",
			blocks: [
				{ type: 'p', text: "**Le plus de passages** récompense les habitués. Il compte les jours où vous avez bouclé le parcours, dans le fuseau horaire du parc : plusieurs tours le même jour comptent pour un." },
			],
		},
		{
			heading: "Qui apparaît dans les classements",
			blocks: [
				{
					type: 'list',
					items: [
						"Vous devez être connecté pour voir les classements. Sans connexion, une page de parcours affiche quand même le parcours et un lien **Se connecter**.",
						"Le temps d'une sortie que les autres ne peuvent pas voir ne leur est pas montré.",
						"Vous ne voyez pas les personnes que vous avez bloquées, et elles ne vous voient pas.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Une sortie est comparée aux parcours de parc sur nos serveurs peu après son enregistrement ou son import, quel que soit l'appareil. Un nouveau temps peut mettre quelques minutes à apparaître dans un classement." },
			],
		},
	],
	sources: {
		title: "c0967d2bf224e3d2",
		summary: "6a173631b44944bc",
		"s0.heading": "216fc084817bfda9",
		"s0.b0": "a96a5717c602367f",
		"s0.b1.i0": "a8567bc2512800d1",
		"s0.b1.i1": "420575263613791d",
		"s0.b1.i2": "d69fbf280d3b46a0",
		"s0.b1.i3": "a75477f7d5a5a5bc",
		"s0.b2": "6a9e63c1eec9c80f",
		"s1.heading": "0026d1ddae689c8a",
		"s1.b0": "f00cd3cca5bfc92f",
		"s1.b1": "36e6dc7fd586b7d7",
		"s2.heading": "5ba4de4e9cb351a4",
		"s2.b0": "f5cb979a283038fa",
		"s2.b1": "6afb246fc0e80841",
		"s3.heading": "f90c634a3c69c00f",
		"s3.b0.i0": "8bab47facf52e4fd",
		"s3.b0.i1": "c74b158f75754752",
		"s3.b0.i2": "a26ad1f8b547015d",
		"s4.heading": "d62c88ea85d104ce",
		"s4.b0": "23512913978ca5c1",
		"s5.heading": "b119ed9eec93efe3",
		"s5.b0.i0": "bee88a50dcbbbfa2",
		"s5.b0.i1": "25229437ce8179b8",
		"s5.b0.i2": "c95241619d2e3582",
		"s5.b1": "f0b47eeb5f542fe4",
	},
};
