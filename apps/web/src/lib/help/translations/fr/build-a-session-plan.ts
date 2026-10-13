import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'build-a-session-plan',
	source: '12f1d327a3007ce2',
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
};
