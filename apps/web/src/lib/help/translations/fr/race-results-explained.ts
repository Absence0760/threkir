import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-results-explained',
	title: 'Comprendre les résultats de course',
	summary: 'Le sens du temps officiel et du temps puce, le calcul des places, les marques Manuel, Organisateur, DNF, DNS et en attente, et comment rechronométrer depuis votre tracé.',
	sections: [
		{
			heading: 'Temps officiel et temps puce',
			blocks: [
				{
					type: 'list',
					items: [
						'Le **Temps officiel** est mesuré entre le moment où l\'organisateur a donné le GO et celui où vous avez franchi l\'arrivée. Le GO est horodaté par notre serveur : tous les participants partagent donc le même départ.',
						'Le **Temps puce** est mesuré entre le moment où vous avez franchi la ligne de départ du parcours et votre arrivée. Si votre téléphone ou votre montre n\'a vu aucun franchissement de la ligne de départ, il court à partir du moment où vous avez appuyé sur Démarrer sur votre propre appareil, pauses comprises.',
						'Une course en chrono libre n\'a pas de GO, donc pas de temps officiel : son classement affiche votre temps puce, de la ligne de départ à la ligne d\'arrivée.',
						'Le grand temps affiché au classement est votre temps officiel si la course a eu un GO, sinon votre temps puce. Les places sont calculées à partir de ce grand temps.',
					],
				},
				{
					type: 'p',
					text: 'Sur le web, la petite ligne sous un temps se lit par exemple « officiel 41:58 · puce 41:20 ». Dans l\'app mobile, le temps puce s\'affiche sous le temps principal, précédé de « Temps réel », quand il en diffère. Si vous êtes parti en retard, votre temps officiel est plus long que votre temps puce.',
				},
			],
		},
		{
			heading: 'Les places se calculent par parcours',
			blocks: [
				{
					type: 'p',
					text: 'Quand une course comporte plusieurs parcours, chaque parcours a son propre classement et ses propres places. Un coureur du 5K n\'est jamais classé face à un coureur du 10K. Les résultats sans parcours sont regroupés (**Sans parcours** sur la page de l\'événement, **Autres** sur la page en direct).',
				},
				{
					type: 'p',
					text: 'Seuls les coureurs arrivés obtiennent une place. En cas d\'égalité, le résultat arrivé en premier l\'emporte.',
				},
			],
		},
		{
			heading: 'Comment l\'arrivée a été enregistrée',
			blocks: [
				{
					type: 'list',
					items: [
						'**Aucun badge** : le téléphone ou la montre du coureur a chronométré l\'arrivée, au moment où il a franchi la ligne d\'arrivée, ou au cercle de 30 m autour de l\'arrivée sur un parcours sans ligne d\'arrivée. C\'est le cas normal : ni le web ni l\'app mobile ne le signalent.',
						'**Manuel** : le coureur a terminé à la main, soit avec **Terminer la course** après avoir couvert au moins 90 % du parcours, soit avec **Soumettre mon temps** sur le web pendant la course.',
						'**Organisateur** (sur le web, **Modifié par l\'organisateur**) : l\'organisateur a saisi ou corrigé ce résultat, ou le coureur a été marqué DNF quand l\'organisateur a terminé la course.',
					],
				},
			],
		},
		{
			heading: 'DNF et DNS',
			blocks: [
				{
					type: 'list',
					items: [
						'**DNF** (did not finish, abandon) : le coureur est parti mais n\'a pas terminé. Cela arrive quand quelqu\'un choisit **Terminer en abandon (DNF)** avant d\'avoir couvert 90 % du parcours, quand l\'organisateur termine la course alors que le coureur est encore en route, ou quand l\'organisateur l\'enregistre.',
						'**DNS** (did not start, non-partant) : enregistré par le coureur avec **Enregistrer un DNS** ou par l\'organisateur.',
						'Ni l\'un ni l\'autre n\'obtient de place. Sur la page en direct, ils sont listés sous **N\'a pas terminé**.',
					],
				},
			],
		},
		{
			heading: 'Résultats en attente',
			blocks: [
				{
					type: 'p',
					text: 'Si l\'organisateur a désactivé l\'approbation automatique, chaque nouveau résultat attend sa validation. Sur la page de l\'événement sur le web, il affiche **EN ATTENTE** sans place pour l\'instant ; dans l\'app mobile et sur la page en direct, il affiche **En attente**. Dès que l\'organisateur choisit **Approuver**, il prend sa place au classement.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Un **Certificat** de finisher ne peut être téléchargé qu\'une fois un résultat d\'arrivée approuvé.',
				},
			],
		},
		{
			heading: 'Rechronométrer depuis votre tracé',
			blocks: [
				{
					type: 'p',
					text: 'Si votre téléphone a manqué une ligne, si votre résultat est un DNF inattendu, ou si vous avez couru avec une Apple Watch, vous pouvez chronométrer à nouveau votre résultat à partir de la sortie que vous avez enregistrée. Ouvrez la sortie sur le web : si elle appartient à une course, elle affiche **Rechronométrer depuis mon tracé** avec votre résultat actuel à côté de celui que donne votre tracé.',
				},
				{
					type: 'steps',
					items: [
						'Vérifiez les deux colonnes : temps officiel, temps puce, et si le départ et l\'arrivée ont été chronométrés par la ligne.',
						'Choisissez **Rechronométrer le résultat**, puis **Remplacer le résultat**.',
					],
				},
				{
					type: 'list',
					items: [
						'Votre tracé est chronométré par les lignes de départ et d\'arrivée avec lesquelles la course s\'est déroulée, sur la même horloge que celle utilisée par votre téléphone ou votre montre pendant la course.',
						'Vous pouvez rechronométrer jusqu\'à 24 heures après la fin de la course. Ensuite, votre temps, votre parcours et votre distance sont verrouillés, et seul l\'organisateur peut modifier votre temps.',
						'Cela remplace un DNF, un temps terminé à la main et un résultat en attente d\'examen. Cela ne remplace jamais un temps fixé par l\'organisateur, ni un résultat déjà chronométré par les deux lignes ; dans une course en chrono libre, seule une tentative plus rapide chronométrée par les deux lignes le remplace.',
						'Si l\'organisateur approuve les résultats à la main, un résultat rechronométré lui est renvoyé pour approbation.',
					],
				},
			],
		},
		{
			heading: 'Quelque chose semble incorrect',
			blocks: [
				{
					type: 'list',
					items: [
						'Aucun résultat ? Si votre appareil n\'avait pas de réseau à l\'arrivée, il envoie le résultat à la reconnexion, dans les 24 heures qui suivent la fin de la course. Pendant ces mêmes 24 heures, vous pouvez aussi le rechronométrer à partir de votre tracé.',
						'Un DNF qui vous semble erroné, ou un temps décalé ? Demandez à l\'organisateur. Il peut le corriger sur le web, et le résultat portera alors la marque de l\'organisateur.',
					],
				},
				{
					type: 'p',
					text: 'Côté coureur, voir [[guide:racing-in-a-race|Participer à une course en direct]]. Organisateurs : [[guide:race-day-for-hosts|Le jour de la course, côté organisateur]].',
				},
			],
		},
	],
	sources: {
		'title': 'c5d9f999ac691293',
		'summary': '184c2d298bd26fe6',
		's0.heading': 'c64bc4e8176b0753',
		's0.b0.i0': '5c206fcfa0703269',
		's0.b0.i1': 'cb9512f304721331',
		's0.b0.i2': 'd7cbf99a35b6a2ef',
		's0.b0.i3': 'cf4e236435fc2502',
		's0.b1': 'a18a5324618c6db1',
		's1.heading': '280c1a73657807c5',
		's1.b0': '86d271497a41304f',
		's1.b1': '692dd04c06057463',
		's2.heading': '6e3b7d9c6cfced31',
		's2.b0.i0': '35a51ea02054bef1',
		's2.b0.i1': '53388c67a2b02b1b',
		's2.b0.i2': '811f16eecd7e7ab7',
		's3.heading': '6a340a4c16d7e613',
		's3.b0.i0': '6f69c4d43a38c323',
		's3.b0.i1': '3604d88945607e72',
		's3.b0.i2': 'f045b1b42c362f65',
		's4.heading': '5ed96724cf8a0430',
		's4.b0': 'f02bc0251822ab1e',
		's4.b1': 'a9bb4df966953e7a',
		's5.heading': '58d90ac423027da2',
		's5.b0': '8fe61e9de9317b69',
		's5.b1.i0': 'd6fc360bf0506c2c',
		's5.b1.i1': 'b0eb18e5a8270886',
		's5.b2.i0': '7b1ea13025902315',
		's5.b2.i1': 'a97c00d0cbdf91fc',
		's5.b2.i2': '8a9c94b45aba53b2',
		's5.b2.i3': '84812a40e9aafb58',
		's6.heading': 'badeb43244f6c195',
		's6.b0.i0': '9afe7b467f14e81b',
		's6.b0.i1': 'b8f3e2e296b07673',
		's6.b1': '9f40f68ca81e692f',
	},
};
