import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'build-a-gym-routine',
	title: 'Créer une routine de muscu',
	summary: 'Transformez une séance que vous enseignez ou répétez en routine réutilisable avec séries, répétitions, charge, repos et supersets, puis suivez-la en mode guidé ou partagez-la avec votre club.',
	sections: [
		{
			heading: 'Deux façons de commencer',
			blocks: [
				{
					type: 'list',
					items: [
						'De zéro : ouvrez [[route:/gym/routines|Routines]] et appuyez sur **Nouvelle routine**. Sur le web, vous pouvez aussi aller dans [[route:/plans/new|Nouveau plan]] et choisir **Routine de gym**.',
						'À partir d\'une séance déjà enregistrée : ouvrez-la dans votre journal de muscu et appuyez sur **Enregistrer comme routine**. Ses exercices et ses séries deviennent les objectifs de la routine. **Répéter la dernière** démarre plutôt une nouvelle séance à partir de la même.',
					],
				},
				{
					type: 'p',
					text: 'Dans l\'app mobile, ouvrez l\'écran de muscu et touchez **Routines**, puis **Nouvelle routine**.',
				},
			],
		},
		{
			heading: 'La remplir',
			blocks: [
				{
					type: 'steps',
					items: [
						'Donnez-lui un **Nom de la routine** qui désigne la journée plutôt que le premier exercice, par exemple « Bootcamp A ».',
						'Saisissez le nom du premier exercice. Reprenez un nom que vous utilisez déjà, pour que vos records sur ce mouvement restent au même endroit.',
						'Choisissez comment il est **Mesuré en** : poids et répétitions, poids du corps, durée ou distance. Les lignes de série changent pour demander l\'objectif correspondant.',
						'Pour chaque série, indiquez un **Type de série** et ses objectifs, comme les **Répétitions cibles** et le poids, ainsi qu\'un **Repos (s)**. Appuyez sur **Ajouter une série** pour en ajouter d\'autres.',
						'Pour enchaîner deux exercices sans pause, activez **Superset avec l\'exercice suivant** sur le premier.',
						'Appuyez sur **Ajouter un exercice** pour le suivant, et recommencez.',
						'Ouvrez si vous le souhaitez **Avancé** et choisissez une règle de **Progression**, qui propose les chiffres de la séance suivante d\'après le résultat de celle-ci. Laissée sur Aucune, vos objectifs restent exactement tels que vous les avez saisis.',
						'Ajoutez éventuellement des **Notes (facultatif)** et appuyez sur **Enregistrer la routine**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Chaque ligne de série est un objectif, pas un enregistrement. C\'est ce qui préremplit une séance démarrée depuis la routine, et vous pouvez toujours modifier les chiffres en cours de route.',
				},
			],
		},
		{
			heading: 'La suivre',
			blocks: [
				{
					type: 'p',
					text: 'Ouvrez la routine et appuyez sur **Démarrer la routine** (dans l\'app mobile, **Démarrer la séance**). Vous êtes guidé une série à la fois avec votre objectif affiché : notez ce que vous avez fait et appuyez sur **Terminer la série**, ou sur **Passer la série**, avec un minuteur de repos entre les séries. Appuyez sur **Terminer** à la fin et la séance est enregistrée dans votre journal de muscu, avec sa comparaison au plan.',
				},
			],
		},
		{
			heading: 'La partager avec un cours',
			blocks: [
				{
					type: 'list',
					items: [
						'**Publier dans un club** : choisissez le club dans **Choisir un club…** et appuyez sur **Publier**. Elle apparaît dans l\'onglet **Modèles** de ce club sous **Modèles de routine de gym**, où les membres appuient sur **Adopter** pour obtenir leur propre copie. Les modifications d\'une copie ne changent pas votre original.',
						'**Publier dans la bibliothèque publique** : toute personne connectée peut la prévisualiser et l\'adopter. Vos séances enregistrées restent privées.',
					],
				},
				{
					type: 'p',
					text: 'Vous proposez un cours payant autour de cette routine ? Voir [[guide:host-a-paid-gym-class|Organiser un cours payant de HIIT, de renforcement ou de bootcamp]].',
				},
			],
		},
	],
	sources: {
		title: 'e154719ab6c6db3a',
		summary: 'c15dfd024f683826',
		's0.heading': 'a52411b1c11cf590',
		's0.b0.i0': '83c54adc1d0ea60f',
		's0.b0.i1': 'eecbf0bc154dab9e',
		's0.b1': '8f85ecd63a29a0a3',
		's1.heading': 'd222e97495049181',
		's1.b0.i0': '81da95efe111f60e',
		's1.b0.i1': '2d229299f8d76acb',
		's1.b0.i2': '82dd1ff342d922c0',
		's1.b0.i3': '5361d720e294f93d',
		's1.b0.i4': 'eadce6bf2e1f99a2',
		's1.b0.i5': '8e0bc50c1d08b6c7',
		's1.b0.i6': '47f7b227af1d250a',
		's1.b0.i7': '2a9bb2561495600e',
		's1.b1': '52bd55355e109053',
		's2.heading': '958ca26c6a61f02f',
		's2.b0': 'f393e332c6ec9a52',
		's3.heading': 'aab7baa90c561d6b',
		's3.b0.i0': 'd51e222a02a3c044',
		's3.b0.i1': 'fc99e8218cc68a71',
		's3.b1': '28cc92b70c319919',
	},
};
