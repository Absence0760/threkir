import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'how-segment-times-are-measured',
	title: 'Comment les temps de segment sont mesurés',
	summary: 'Les temps des segments et des parcours de parc courent d\'une ligne de départ à une ligne de fin, franchies dans le bon sens, et votre passage le plus rapide compte.',
	sections: [
		{
			heading: 'Lignes de départ et de fin',
			blocks: [
				{
					type: 'p',
					text: 'Chaque segment a une ligne de départ et une ligne de fin, une en travers du chemin à chaque extrémité, orientées dans le sens du segment et s\'étendant sur 15 m de chaque côté. Un parcours de parc est aussi un segment : il est donc chronométré de la même façon.',
				},
				{
					type: 'list',
					items: [
						'Votre temps court du moment où votre course franchit la ligne de départ jusqu\'à celui où elle franchit la ligne de fin.',
						'Chaque franchissement est calculé entre les deux points GPS situés de part et d\'autre de la ligne, et non pris au point qui se trouvait être le plus proche : le temps est donc plus proche du temps réel.',
						'Les deux lignes doivent être franchies dans le sens du segment. En franchir une à l\'envers ne compte pas.',
						'La distance parcourue entre les deux franchissements doit être à 25 % près de la longueur du segment, et sur un parcours de parc vous devez passer par chaque point de contrôle, dans l\'ordre, entre les deux.',
					],
				},
			],
		},
		{
			heading: 'Pourquoi un chemin parallèle ne compte pas',
			blocks: [
				{
					type: 'p',
					text: 'Une course sur un chemin qui longe le segment, à 20 m, passe près des deux extrémités sans jamais traverser les lignes : elle n\'obtient donc pas de temps. L\'aller d\'un itinéraire en aller-retour qui ne fait que passer près de la fin n\'en obtient pas non plus.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Lancez l\'enregistrement un peu avant la ligne de départ. Une course dont l\'enregistrement commence sur la ligne, ou après, ne la franchit jamais et n\'obtient pas de temps sur ce segment.',
				},
			],
		},
		{
			heading: 'Plusieurs passages',
			blocks: [
				{
					type: 'list',
					items: [
						'Si votre course passe plusieurs fois sur le segment, votre passage le plus rapide compte.',
						'Un échauffement qui repasse par la ligne de départ n\'allonge pas votre temps : le chrono part de votre dernier franchissement de la ligne de départ avant la fin.',
						'Sur une boucle, chaque tour complet est chronométré et ton tour le plus rapide compte. Quand le départ et la fin sont la même ligne, le franchissement qui termine un tour lance aussi le suivant.',
					],
				},
			],
		},
		{
			heading: 'Segments sans lignes',
			blocks: [
				{
					type: 'p',
					text: 'Un segment trop court à une extrémité pour y placer une ligne n\'a pas de lignes. Il est toujours chronométré à l\'ancienne : votre course doit passer à moins de 35 m de son départ, puis à moins de 35 m de sa fin.',
				},
			],
		},
		{
			heading: 'Efforts plus anciens',
			blocks: [
				{
					type: 'p',
					text: 'Les efforts enregistrés avant que les segments aient des lignes ont été mesurés à l\'ancienne, en passant près du départ et de la fin. Chacun est remesuré avec les lignes la prochaine fois que son coureur ouvre la course sur le site web. Son temps peut changer, et il peut disparaître si la course n\'a jamais franchi les lignes.',
				},
				{
					type: 'p',
					text: 'Tant que tous les efforts d\'un segment n\'ont pas été remesurés, son classement indique que certains efforts plus anciens ont été mesurés à l\'ancienne.',
				},
			],
		},
	],
	sources: {
		title: 'af6ac26d6646f774',
		summary: 'a18775a50f19720a',
		's0.heading': 'e4b2458df12fdaf3',
		's0.b0': 'cd68d1e94a0f5ab9',
		's0.b1.i0': '6f3bd850e275ed2a',
		's0.b1.i1': '1f53338704ded34d',
		's0.b1.i2': 'bbbd3c6ebb557922',
		's0.b1.i3': '6b8289f9cfe75cdc',
		's1.heading': 'a7fcd26c4192d17b',
		's1.b0': '433e0989f5c0bcdb',
		's1.b1': '762d24e1e2186155',
		's2.heading': '07aa1107fe80687c',
		's2.b0.i0': 'd1cc20d8bffef410',
		's2.b0.i1': '49b20e543d91d563',
		's2.b0.i2': '768a4bc2c007e9bb',
		's3.heading': '6ce1d76024b4fe1f',
		's3.b0': '2f8dce267fbf234c',
		's4.heading': 'f2e748afe43f1604',
		's4.b0': '73985bbd2197a3b7',
		's4.b1': '02549166218656ab',
	},
};
