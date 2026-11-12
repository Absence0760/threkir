import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'take-attendance',
	title: 'Faire l\'appel à un cours',
	summary: 'Notez qui est réellement venu à chaque occurrence d\'un cours, indépendamment de qui avait dit venir, sur le web ou dans l\'app mobile.',
	sections: [
		{
			heading: 'Qui peut faire l\'appel, et où',
			blocks: [
				{
					type: 'p',
					text: 'L\'appel concerne les événements de type **Cours**, et seuls les admins et organisateurs d\'événements du club peuvent le faire. Il fonctionne de la même façon sur le web et dans l\'app mobile : vous pouvez donc le faire depuis votre téléphone, face à votre groupe.',
				},
				{
					type: 'p',
					text: 'Il est distinct de la réponse à l\'événement. Une personne peut avoir répondu **Participe**, ou être inscrite et avoir payé, et quand même être marquée absente ; noter la présence ne modifie jamais son inscription et ne rembourse personne.',
				},
			],
		},
		{
			heading: 'Noter qui est venu',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez le cours. S\'il se répète, utilisez **Choisir une occurrence** pour sélectionner la date du jour, car la présence est enregistrée par occurrence.',
						'Faites défiler jusqu\'à la liste des participants.',
						'À côté de chaque personne, appuyez sur **Marquer comme présent** ou **Marquer comme absent**.',
						'Vous vous êtes trompé de bouton ? Appuyez de nouveau sur le même bouton pour effacer votre choix.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Vous n\'êtes pas obligé de marquer tout le monde. Les personnes non marquées n\'ont simplement aucune présence enregistrée.',
				},
			],
		},
		{
			heading: 'Ce que voient les autres',
			blocks: [
				{
					type: 'p',
					text: 'Les autres personnes qui consultent le cours voient une étiquette **Présent** ou **Absent** à côté de chaque nom que vous avez marqué, mais ne peuvent pas la modifier.',
				},
				{
					type: 'p',
					text: 'La présence n\'ajoute pas le cours à l\'historique d\'entraînement de qui que ce soit. Les participants le font eux-mêmes avec **Enregistrer comme séance** sur la page du cours, ou en suivant le plan de séance du cours : voir [[guide:build-a-session-plan|Créer un plan de séance]].',
				},
			],
		},
	],
	sources: {
		title: '8e94f2c520c4725e',
		summary: '19234d07e67c5a4f',
		's0.heading': 'faee9310c256dbe3',
		's0.b0': 'f196a1f6af265a97',
		's0.b1': '4e5ee5d97f6345cd',
		's1.heading': '606dabb8e1030b7c',
		's1.b0.i0': 'd74050897fbc9e6d',
		's1.b0.i1': '2d151dfb1f62d0b0',
		's1.b0.i2': 'aee700bc763c5ade',
		's1.b0.i3': '3222de96fadf77f6',
		's1.b1': '1ca4fbd7f7608965',
		's2.heading': '7e87e01018106f7c',
		's2.b0': '83dbaf9e7ca920df',
		's2.b1': '1195e880106739dc',
	},
};
