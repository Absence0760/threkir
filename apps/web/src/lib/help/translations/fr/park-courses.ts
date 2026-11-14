import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'park-courses',
	title: "Parcours des parcs : points de contrôle, saisons, mois et classements",
	summary: "Comment un parcours de parc chronomètre votre course, pourquoi chaque point de contrôle compte, quand commencent une saison et un mois et comment se classent Plus rapides et Le plus de passages.",
	sections: [
		{
			heading: "Qu'est-ce qu'un parcours de parc",
			blocks: [
				{ type: 'p', text: "Un parcours de parc est un parcours de contre-la-montre fixe sur un sentier d'un parc d'État ou d'un parc national. Il n'y a ni organisateur ni jour de compétition : courez-le quand le parc est ouvert, et toute course qui couvre l'ensemble du parcours est chronométrée. Retrouvez-les sous **À courir quand vous voulez** dans [[route:/races|Épreuves et parcours]], les plus proches d'abord dès que vous indiquez un lieu, ou parcourez-les tous dans [[route:/parks|Parcours des parcs]]. Sélectionnez **Parcours** en haut d'Épreuves et parcours pour afficher tous les parcours seuls, sans le calendrier des épreuves." },
				{
					type: 'list',
					items: [
						"C'est un contre-la-montre, pas une course. Le sentier reste ouvert à tous et personne ne l'encadre : respectez le règlement du parc et cédez le passage aux autres usagers du sentier.",
						"Chaque page de parcours indique la distance, le dénivelé positif, la forme, le revêtement et la difficulté, l'origine du tracé et si le parcours est ouvert.",
						"Sélectionnez **Suivre ce parcours** pour suivre le parcours comme un itinéraire. Cette option n'est pas proposée tant que le parcours est fermé.",
						"La rubrique **Description du parcours** de la page du parcours indique où se garer et chaque changement de direction dans l'ordre, par nom de sentier, avec les ponts, les gués, les changements de revêtement et les montées. Elle est rédigée à partir des données cartographiques ; tant que personne ne l'a vérifiée sur place, c'est indiqué au-dessus de la liste. La même description figure dans le fichier GPX du parcours.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Un parcours fermé ne prend aucun nouveau temps : une course dessus pendant sa fermeture n'est pas chronométrée, et les temps qu'il a déjà restent dans ses classements. Merci de ne pas le courir avant sa réouverture. La page indique quand son statut a été vérifié pour la dernière fois." },
			],
		},
		{
			heading: "Points de contrôle : pourquoi les raccourcis ne comptent jamais",
			blocks: [
				{ type: 'p', text: "En plus du départ et de l'arrivée, un parcours peut avoir des points de contrôle en chemin. Votre course n'est chronométrée que si elle passe par chaque point de contrôle, dans l'ordre, entre le départ et l'arrivée. Une course qui coupe un virage, saute un lacet ou traverse par le milieu manque un point de contrôle et n'obtient pas de temps." },
				{ type: 'p', text: "Restez sur le sentier balisé. Couper un sentier l'abîme, et les parcs le considèrent comme une infraction à leur règlement." },
			],
		},
		{
			heading: "Les saisons suivent l'heure du parc",
			blocks: [
				{ type: 'p', text: "Une saison est une année civile dans le fuseau horaire du parc, pas le vôtre. Les classements repartent à zéro à minuit le 1er janvier là où se trouve le parc." },
				{ type: 'p', text: "Par exemple, une course qui démarre à 22 h le 31 décembre dans un parc de Virginie compte pour cette année-là, même si votre téléphone est réglé sur un fuseau où l'on est déjà le 1er janvier." },
			],
		},
		{
			heading: "Le classement Plus rapides",
			blocks: [
				{
					type: 'list',
					items: [
						"**Plus rapides** classe chaque coureur selon son meilleur temps sur le parcours. Vous apparaissez une seule fois, avec votre meilleure course.",
						"Il affiche cette année par défaut. Sélectionnez **Ce mois-ci** pour le mois en cours, ou **Depuis toujours** pour les meilleurs temps jamais réalisés.",
						"Filtrez par genre ou par tranche d'âge. Le filtre d'âge n'inclut que les coureurs qui ont donné leur consentement aux données de santé, il peut donc être plus court que le classement complet.",
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
			heading: "Les mois : un nouveau classement chaque mois",
			blocks: [
				{ type: 'p', text: "Les deux classements existent aussi mois par mois. Un mois est un mois civil dans le fuseau horaire du parc, de minuit le 1er à minuit le 1er du mois suivant : une course à 23 h 30 le 31 octobre, à l'heure du parc, compte donc pour octobre." },
				{
					type: 'list',
					items: [
						"Sélectionnez **Ce mois-ci** pour voir le mois en cours, et utilisez les flèches à côté du nom du mois pour revenir aux mois précédents.",
						"Chaque parcours sur la page d'un parc indique combien de personnes l'ont couru ce mois-ci.",
						"Un temps sur un parcours de parc, sur la page de votre course, indique sa place ce mois-là et cette année-là, par exemple n° 2 en novembre, n° 9 en 2026. L'autocollant **Parcours de parc** d'une image partagée montre la place du mois, et aussi celle de l'année quand elle est dans les 10 premières.",
						"Quand un mois se termine à l'heure du parc, vous recevez dans votre boîte de réception un message avec votre meilleur temps du mois sur chaque parcours que vous avez couru. Désactivez-le avec **Mois sur les parcours de parc** : sur le web dans [[route:/settings/notifications|Notifications]], dans l'app mobile sous **Notifications** dans l'onglet **Vous**.",
						"Les badges des mois au parc comptent les mois où vous avez terminé un parcours de parc, à 3, 6, 12 et 24 mois. Ils comptent les parcours terminés, jamais les places.",
					],
				},
			],
		},
		{
			heading: "Qui apparaît dans les classements",
			blocks: [
				{
					type: 'list',
					items: [
						"Vous devez être connecté pour voir les classements. Sans connexion, une page de parcours affiche quand même le parcours et un lien **Se connecter**.",
						"Le temps d'une course que les autres ne peuvent pas voir ne leur est pas montré.",
						"Vous ne voyez pas les personnes que vous avez bloquées, et elles ne vous voient pas.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Une course est comparée aux parcours de parc sur nos serveurs peu après son enregistrement ou son import, quel que soit l'appareil. Un nouveau temps peut mettre quelques minutes à apparaître dans un classement." },
			],
		},
	],
	sources: {
		title: "80ff9e4c22672c3e",
		summary: "a8d0d3cdf47ef5c6",
		"s0.heading": "216fc084817bfda9",
		"s0.b0": "c202f382c7f5c297",
		"s0.b1.i0": "a8567bc2512800d1",
		"s0.b1.i1": "420575263613791d",
		"s0.b1.i2": "d69fbf280d3b46a0",
		"s0.b1.i3": "a75477f7d5a5a5bc",
		"s0.b2": "a9aa6fec9968fc90",
		"s1.heading": "0026d1ddae689c8a",
		"s1.b0": "f00cd3cca5bfc92f",
		"s1.b1": "36e6dc7fd586b7d7",
		"s2.heading": "5ba4de4e9cb351a4",
		"s2.b0": "f5cb979a283038fa",
		"s2.b1": "6afb246fc0e80841",
		"s3.heading": "f90c634a3c69c00f",
		"s3.b0.i0": "8bab47facf52e4fd",
		"s3.b0.i1": "01322b98d3fa4762",
		"s3.b0.i2": "1b3d5a9034e460c5",
		"s4.heading": "d62c88ea85d104ce",
		"s4.b0": "23512913978ca5c1",
		"s5.heading": "2158104d68549d3e",
		"s5.b0": "f8cebd1b6b6f6d5c",
		"s5.b1.i0": "95832d49c27d961e",
		"s5.b1.i1": "e5fd55e453a25d9a",
		"s5.b1.i2": "0220ee50a2c3ffc2",
		"s5.b1.i3": "3c988cac91d6d886",
		"s5.b1.i4": "9f0fedf00dcae221",
		"s6.heading": "b119ed9eec93efe3",
		"s6.b0.i0": "bee88a50dcbbbfa2",
		"s6.b0.i1": "25229437ce8179b8",
		"s6.b0.i2": "c95241619d2e3582",
		"s6.b1": "f0b47eeb5f542fe4",
	},
};
