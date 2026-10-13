import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'build-a-session-plan',
	title: 'Créer un plan de séance de yoga, de pilates ou de mobilité',
	summary: 'Rédigez une séquence minutée de postures tenues, d\'enchaînements et de répétitions, avec mouvements par côté et indications, puis enseignez-la, joignez-la à un cours et suivez-la.',
	sections: [
		{
			heading: 'Où le créer',
			blocks: [
				{
					type: 'p',
					text: 'Les plans de séance se rédigent sur le web. L\'app mobile les liste et les lance, mais n\'a pas encore d\'éditeur.',
				},
				{
					type: 'list',
					items: [
						'Pour vous-même : ouvrez [[route:/plans/new|Nouveau plan]] et choisissez **Plan de séance**, ou appuyez sur **Nouvelle séance** dans [[route:/sessions|Séances]].',
						'Pour votre club : dans l\'onglet **Modèles** du club, appuyez sur **Ajouter un modèle** et choisissez **Plan de séance**. Il est aussitôt enregistré comme modèle de club.',
					],
				},
			],
		},
		{
			heading: 'Le remplir',
			blocks: [
				{
					type: 'steps',
					items: [
						'Donnez-lui un **Titre** qui nomme la séquence, comme « Flow d\'ouverture des hanches, 45 min ».',
						'Ajoutez une **Discipline** (par exemple Vinyasa yoga) et le **Matériel** à prévoir, comme un tapis ou un reformer.',
						'Appuyez si vous le souhaitez sur **Ajouter un bloc** pour le découper en sections comme Échauffement, Debout et Retour au calme. Un plan sans blocs se déroule d\'une traite.',
						'Appuyez sur **Ajouter un mouvement** pour chaque posture ou exercice et saisissez son nom dans **Mouvement**.',
						'Choisissez son **Type** : **Tenue** pour une posture minutée, **Flow** pour un enchaînement de mouvements minuté, ou **Répét.** pour un exercice compté. Saisissez ensuite les **Secondes** ou les **Répétitions**, et le **Bloc** auquel il appartient.',
						'Cochez **Par côté (gauche & droite)** pour tout ce qui se fait de chaque côté. Le mouvement est exécuté une fois de chaque côté, il dure donc deux fois plus longtemps.',
						'Ajoutez si vous le souhaitez un **Tempo** et une **Indication**, la consigne de respiration ou d\'alignement affichée à côté du mouvement pendant qu\'on le suit.',
						'Vérifiez la durée estimée que l\'éditeur calcule pour vous, puis appuyez sur **Enregistrer**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Les noms de mouvements sont suggérés à partir de vos plans précédents pendant la saisie. Choisir une suggestion garantit que la même posture est écrite de la même façon partout.',
				},
			],
		},
		{
			heading: 'Le joindre à un cours',
			blocks: [
				{
					type: 'list',
					items: [
						'En créant un cours, choisissez le plan sous **Plan de séance**.',
						'Le cours est déjà créé ? Sur la page du cours, les organisateurs appuient sur **Associer à un événement de cours** dans la carte **Séquence de la séance**.',
					],
				},
				{
					type: 'p',
					text: 'Les participants voient alors la séquence complète sur la page du cours. Un plan privé reste privé pour tous les autres, mais les personnes inscrites au cours auquel vous le joignez peuvent le voir.',
				},
			],
		},
		{
			heading: 'Le suivre',
			blocks: [
				{
					type: 'p',
					text: 'Ouvrez le plan et appuyez sur **Démarrer la séance**. Les postures tenues et les enchaînements minutés avancent tout seuls ; pour les répétitions, appuyez sur **Terminé** une fois fini. Vous pouvez mettre en **Pause**, **Reprendre**, **Passer** une étape ou **Abandonner**. À la fin, la séance est enregistrée dans votre journal de muscu.',
				},
				{
					type: 'p',
					text: 'L\'app mobile propose le même suivi, lit les indications à voix haute, garde l\'écran allumé et continue de compter le temps si vous passez à une autre app.',
				},
			],
		},
		{
			heading: 'Le partager',
			blocks: [
				{
					type: 'list',
					items: [
						'**Rendre public** permet à tout le monde de le trouver et de le suivre. **Copier le lien de partage** rend le plan public et copie un lien qui fonctionne sans connexion.',
						'**Publier dans un club** : choisissez le club dans **Choisir un club…** et appuyez sur **Publier**. Il apparaît sous **Modèles de séance** dans l\'onglet **Modèles** du club, et les membres appuient sur **Adopter** pour obtenir leur propre copie.',
					],
				},
			],
		},
	],
	sources: {
		title: '2761214d4528b755',
		summary: '6ed93f306126bfd5',
		's0.heading': '75ab7687d1fdc4e6',
		's0.b0': '4c2393e2453c0847',
		's0.b1.i0': 'be6a427f8e3575ab',
		's0.b1.i1': '43033b89a725981f',
		's1.heading': 'd222e97495049181',
		's1.b0.i0': 'e1da2dcf855fd8cd',
		's1.b0.i1': '117837344c17aa7d',
		's1.b0.i2': '2e19d15f6adb30c7',
		's1.b0.i3': '4178a74d986586c6',
		's1.b0.i4': 'ba82220d774c7f84',
		's1.b0.i5': '03673097f36c78e9',
		's1.b0.i6': 'd02405ef4e9be33a',
		's1.b0.i7': '4f883b9f98fe5258',
		's1.b1': '63d86fc0ace9cb60',
		's2.heading': '27bf4831df1b4047',
		's2.b0.i0': '08f6e2680c9d0de7',
		's2.b0.i1': '91f068b693756ac2',
		's2.b1': '9021887b2281f1ca',
		's3.heading': '273869c12606c741',
		's3.b0': 'bfc8888c6226cf77',
		's3.b1': '4c67ea01c09f80f8',
		's4.heading': '692991f8b622c079',
		's4.b0.i0': '548fec5550dfaa6b',
		's4.b0.i1': '21ced8342dc5228c',
	},
};
