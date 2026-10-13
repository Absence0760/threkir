import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-results-explained',
	title: 'Comprendre les résultats de course',
	summary: 'Ce que signifient le temps officiel et le temps puce, comment les places sont calculées par parcours, et ce qu\'indiquent les marques Manuel, Organisateur, DNF, DNS et en attente.',
	sections: [
		{
			heading: 'Temps officiel et temps puce',
			blocks: [
				{
					type: 'list',
					items: [
						'Le **Temps officiel** est mesuré entre le moment où l\'organisateur a donné le GO et celui où vous avez franchi l\'arrivée. Le GO est horodaté par notre serveur : tous les participants partagent donc le même départ.',
						'Le **Temps puce** est mesuré entre le moment où vous avez appuyé sur Démarrer sur votre propre appareil et votre arrivée, pauses comprises.',
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
						'**Aucun badge** : le téléphone ou la montre du coureur a détecté la ligne d\'arrivée. C\'est le cas normal : ni le web ni l\'app mobile ne le signalent.',
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
			heading: 'Quelque chose semble incorrect',
			blocks: [
				{
					type: 'list',
					items: [
						'Aucun résultat ? Si votre appareil n\'avait pas de réseau à l\'arrivée, il envoie le résultat à la reconnexion, dans les 24 heures qui suivent la fin de la course.',
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
		title: 'c5d9f999ac691293',
		summary: '7d62d231e5ab41c2',
		's0.heading': 'c64bc4e8176b0753',
		's0.b0.i0': '5c206fcfa0703269',
		's0.b0.i1': 'd4a920d1ad78f899',
		's0.b0.i2': 'cf4e236435fc2502',
		's0.b1': 'a18a5324618c6db1',
		's1.heading': '280c1a73657807c5',
		's1.b0': '86d271497a41304f',
		's1.b1': '692dd04c06057463',
		's2.heading': '6e3b7d9c6cfced31',
		's2.b0.i0': '9dec22cfdf8763a9',
		's2.b0.i1': '53388c67a2b02b1b',
		's2.b0.i2': '811f16eecd7e7ab7',
		's3.heading': '6a340a4c16d7e613',
		's3.b0.i0': '6f69c4d43a38c323',
		's3.b0.i1': '3604d88945607e72',
		's3.b0.i2': 'f045b1b42c362f65',
		's4.heading': '5ed96724cf8a0430',
		's4.b0': 'f02bc0251822ab1e',
		's4.b1': 'a9bb4df966953e7a',
		's5.heading': 'badeb43244f6c195',
		's5.b0.i0': '3a602354cdf2e6f2',
		's5.b0.i1': 'b8f3e2e296b07673',
		's5.b1': '9f40f68ca81e692f',
	},
};
