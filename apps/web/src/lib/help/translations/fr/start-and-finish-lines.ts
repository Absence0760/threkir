import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'start-and-finish-lines',
	title: 'Lignes de départ et d\'arrivée',
	summary: 'Ce que sont les lignes de départ et d\'arrivée d\'un parcours, comment elles sont placées pour vous, et comment les déplacer, les faire pivoter, les élargir ou les placer vous-même.',
	sections: [
		{
			heading: 'Qu\'est-ce qu\'une ligne',
			blocks: [
				{
					type: 'p',
					text: 'Chaque parcours d\'une course a une ligne de départ et une ligne d\'arrivée. Une ligne traverse le parcours en un point, est orientée dans le sens où avancent les coureurs et s\'étend sur une distance fixe de chaque côté. Un coureur ne la franchit qu\'en la traversant dans ce sens, à l\'intérieur de sa portée.',
				},
				{
					type: 'p',
					text: 'C\'est la différence avec un point d\'arrivée entouré d\'un cercle de 30 m. Un cercle compte toute personne qui s\'en approche : un coureur sur un chemin qui longe le parcours, ou à l\'aller d\'un parcours en aller-retour qui revient par le même chemin. Une ligne, non, car ces coureurs ne la traversent jamais dans le bon sens.',
				},
			],
		},
		{
			heading: 'Des lignes placées pour vous',
			blocks: [
				{
					type: 'p',
					text: 'Quand un parcours a un itinéraire, il en tire ses deux lignes. La ligne de départ se trouve sur le premier point de l\'itinéraire, orientée dans le sens de l\'itinéraire. La ligne d\'arrivée se trouve sur son dernier point, orientée dans le sens où l\'itinéraire arrive. Chacune s\'étend sur 15 m de chaque côté. Elles suivent l\'itinéraire : modifiez l\'itinéraire et elles se déplacent avec lui.',
				},
				{
					type: 'p',
					text: 'Les lignes apparaissent une fois l\'événement enregistré avec au moins un parcours. Ouvrez l\'événement, choisissez **Modifier l\'événement** et repérez **Lignes de départ et d\'arrivée**. Chaque parcours a une carte et une rangée par ligne, qui indique d\'où vient la ligne : **Issue de l\'itinéraire**, **Placée par un organisateur** ou **Aucune**.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si le propriétaire de l\'itinéraire a une zone de confidentialité sur le départ ou la fin de l\'itinéraire, cette extrémité est masquée pour tous les autres : elle n\'a donc pas de ligne. Placez cette ligne vous-même.',
				},
			],
		},
		{
			heading: 'Déplacer, faire pivoter ou élargir une ligne',
			blocks: [
				{
					type: 'steps',
					items: [
						'À côté de **Ligne de départ** ou **Ligne d\'arrivée**, choisissez **Modifier**.',
						'Sur la carte, faites glisser le milieu de la ligne pour la déplacer, et faites glisser sa poignée pour la faire pivoter. Si la carte est désactivée, choisissez **Charger la carte**, ou laissez la carte de côté et saisissez plutôt les valeurs.',
						'Ou saisissez la **Latitude**, la **Longitude** et la **Direction (degrés)**. La direction est le sens dans lequel les coureurs franchissent la ligne, dans le sens horaire depuis le nord : 0 est le nord, 90 l\'est, 180 le sud et 270 l\'ouest.',
						'Réglez la **Portée de chaque côté**, de 5 à 100 m. Prévoyez-la assez large pour couvrir toute la route ou tout le chemin, avec un peu de marge.',
						'Choisissez **Enregistrer la ligne**.',
					],
				},
				{
					type: 'p',
					text: 'Chaque ligne s\'enregistre séparément, immédiatement ; vous n\'avez pas besoin d\'enregistrer l\'événement. Une ligne que vous avez déplacée affiche **Placée par un organisateur**. Choisissez **Revenir à l\'itinéraire** pour la remettre là où l\'itinéraire la place.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Une ligne que vous avez placée reste exactement où vous l\'avez mise, même si vous modifiez ensuite l\'itinéraire du parcours. Après avoir modifié un itinéraire, vérifiez les avertissements sous chaque ligne.',
				},
			],
		},
		{
			heading: 'Avertissements dans l\'éditeur',
			blocks: [
				{
					type: 'list',
					items: [
						'La ligne est à plus de 100 m de l\'itinéraire du parcours. Vérifiez qu\'elle est au bon endroit.',
						'La ligne est orientée à contresens de l\'itinéraire : les coureurs qui suivent l\'itinéraire la franchiraient à l\'envers. Faites-la pivoter d\'un demi-tour.',
						'L\'itinéraire franchit sa propre ligne d\'arrivée avant la fin, comme un parcours en tours ou une piste. L\'arrivée par la ligne est alors désactivée pour ce parcours, et les coureurs terminent en appuyant sur Arrêter ou Terminer.',
					],
				},
			],
		},
		{
			heading: 'Parcours sans itinéraire',
			blocks: [
				{
					type: 'p',
					text: 'Un parcours sans itinéraire n\'a pas de lignes tant que vous ne les placez pas. Choisissez **Placer la ligne de départ** ou **Placer la ligne d\'arrivée**. Si vous avez d\'abord déplacé la carte jusqu\'à l\'endroit voulu, la ligne commence au milieu de la carte ; sinon, saisissez sa position. Réglez ensuite sa direction et sa portée, puis choisissez **Enregistrer la ligne**. **Supprimer la ligne** retire une ligne que vous avez placée.',
				},
			],
		},
		{
			heading: 'Les lignes sont figées au départ d\'une course',
			blocks: [
				{
					type: 'p',
					text: 'Quand vous armez une course (pour une course en chrono libre, à l\'ouverture de sa fenêtre), les lignes de chaque parcours sont copiées pour cette course. Chaque coureur franchit alors les mêmes lignes, quels que soient les changements pendant la course. Une modification faite ensuite s\'applique à partir de la course suivante. La page de l\'événement et la page en direct de la course affichent les lignes avec lesquelles la course a été armée.',
				},
			],
		},
		{
			heading: 'Vérifications avant une course',
			blocks: [
				{
					type: 'p',
					text: 'Avant qu\'une course soit armée, les lignes de chaque parcours sont vérifiées, sur le web et dans l\'app mobile. Un avertissement vous laisse **Armer quand même** ; un problème marqué **À corriger :** empêche d\'armer la course tant que vous ne l\'avez pas corrigé dans l\'éditeur d\'événement sur le web.',
				},
				{
					type: 'list',
					items: [
						'Un parcours sans ligne ni point d\'arrivée : un avertissement, car ses coureurs terminent à la main. Pour une course en chrono libre, il faut le corriger.',
						'Un parcours sans ligne de départ : pour une course en chrono libre, il faut le corriger. Les autres courses peuvent partir sans.',
						'Un itinéraire qui franchit sa propre ligne d\'arrivée avant la fin : un avertissement, car l\'arrivée par la ligne est désactivée pour ce parcours. Pour une course en chrono libre, il faut le corriger.',
						'Une ligne à plus de 100 m de l\'itinéraire : un avertissement, quel que soit le type de course.',
					],
				},
				{
					type: 'p',
					text: 'Le type de course que vous organisez se règle sous **Comment la course démarre** ; voir [[guide:choose-how-your-race-starts|Choisir comment votre course démarre]].',
				},
			],
		},
	],
	sources: {
		title: 'e32b975b30a0bfdf',
		summary: '007484d24c448df5',
		's0.heading': 'b2178bb9e4c07f85',
		's0.b0': '7b22e9bee9ea6e44',
		's0.b1': 'e18c2ba36732dafb',
		's1.heading': '6ae01aac1742fa11',
		's1.b0': '98879a39846cccd2',
		's1.b1': '1121c7b877f6a658',
		's1.b2': '5d09b8607f6a2f22',
		's2.heading': 'b839a49fc88eb9bb',
		's2.b0.i0': 'f9a4dd08d366b730',
		's2.b0.i1': '0bfc28ecb00a6d5b',
		's2.b0.i2': '29eaf88dee6df1d8',
		's2.b0.i3': '082f59f63580a00b',
		's2.b0.i4': '008936c6ea875617',
		's2.b1': 'e6292e6047487d65',
		's2.b2': '5bad76f945b81e03',
		's3.heading': '49bbc9db5d4c7163',
		's3.b0.i0': 'c519f8cea9bd87d0',
		's3.b0.i1': 'e08a656a24f1ed58',
		's3.b0.i2': 'aa848004795cf7a1',
		's4.heading': '3bd16f8003e613ef',
		's4.b0': 'adfbcab88a7c3e90',
		's5.heading': 'be581f997710aa1d',
		's5.b0': 'b691f01dae47a921',
		's6.heading': 'a1cbd797f4858538',
		's6.b0': '3ab85eab34b17f4c',
		's6.b1.i0': 'e5b89e5070aad84a',
		's6.b1.i1': '2d67c55e24d207a9',
		's6.b1.i2': '1ecbd8a36af71c78',
		's6.b1.i3': '84f19ca583307307',
		's6.b2': 'cfbf64534e49a993',
	},
};
