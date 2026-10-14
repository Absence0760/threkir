import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-day-for-hosts',
	title: 'Le jour de la course, côté organisateur',
	summary: 'Armez la course, donnez le GO, suivez-la en direct, terminez-la, puis approuvez et corrigez les résultats.',
	sections: [
		{
			heading: 'Qui peut gérer une course',
			blocks: [
				{
					type: 'p',
					text: 'Le contrôle de course apparaît sur la page de l\'événement pour les propriétaires et les admins du club, ainsi que pour les membres qui ont le rôle **Directeur de course**. Sur le web, c\'est la carte **Contrôle de course** ; dans l\'app mobile, c\'est la carte **CONTRÔLE DE COURSE** sur l\'écran de l\'événement. Les deux permettent d\'approuver et de modifier les résultats.',
				},
				{
					type: 'p',
					text: 'Vérifiez d\'abord que l\'événement a des parcours — voir [[guide:set-up-a-race|Organiser une course]].',
				},
				{
					type: 'illustration',
					id: 'race-day-for-hosts',
					alt: 'Le jour de course en quatre étapes, de gauche à droite : armer la course, donner le GO, la suivre en direct, puis la terminer à l\'arrivée.',
				},
			],
		},
		{
			heading: '1. Armer la course',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez l\'événement et choisissez l\'occurrence du jour s\'il se répète.',
						'Laissez **Approuver automatiquement les résultats soumis** coché pour publier les résultats dès leur arrivée, ou décochez-le pour approuver chacun vous-même. (Dans l\'app mobile, l\'option s\'intitule **Approuver automatiquement les temps soumis**.)',
						'Choisissez **Armer la course** quand tout le monde est rassemblé.',
					],
				},
				{
					type: 'p',
					text: 'Les coureurs qui ont répondu **Je participe** voient alors **Course armée** dans l\'onglet Courir de leur téléphone et « COURSE PRÊTE » sur leur montre Wear OS.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'L\'état armé est un état d\'attente. Rien n\'est chronométré et aucun résultat ne peut être enregistré tant que vous n\'avez pas donné le GO.',
				},
			],
		},
		{
			heading: '2. Donner le GO',
			blocks: [
				{
					type: 'p',
					text: 'Appuyez sur **GO** sur le web (**Lancer le Go** dans l\'app mobile) au moment où la course part.',
				},
				{
					type: 'p',
					text: 'L\'heure de départ est horodatée par notre serveur, et non par votre appareil : c\'est donc le même top départ pour chaque coureur, même si l\'horloge de votre téléphone a quelques secondes d\'écart. Le temps officiel de chaque coureur est mesuré à partir de ce top.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Le GO ne lance l\'enregistrement de personne. Les coureurs appuient eux-mêmes sur Démarrer sur leur téléphone ou leur montre, soit sur la ligne pendant que la course est armée (l\'enregistrement est rattaché à la course au GO), soit après avoir vu **Course EN DIRECT**. Rappelez-leur d\'en lancer un.',
				},
			],
		},
		{
			heading: '3. Suivre la course en direct',
			blocks: [
				{
					type: 'list',
					items: [
						'La carte de contrôle de course affiche **En cours** avec le temps écoulé.',
						'Choisissez **Vue spectateur** pour la carte en direct, le classement **Sur le parcours** et le classement **Terminé**. Voir [[guide:follow-a-race-live|Suivre une course en direct]].',
						'Les appareils des coureurs enregistrent automatiquement leur arrivée sur la ligne : les résultats apparaissent donc sur la page de l\'événement pendant que la course se déroule encore.',
					],
				},
			],
		},
		{
			heading: '4. Terminer la course',
			blocks: [
				{
					type: 'steps',
					items: [
						'Quand le dernier coureur est arrivé (ou que votre barrière horaire est passée), choisissez **Terminer la course**.',
						'La confirmation, sur le web comme dans l\'app mobile, indique combien de coureurs partis n\'ont pas de résultat. Ces coureurs seront marqués DNF.',
						'Confirmez avec **Terminer la course**.',
					],
				},
				{
					type: 'p',
					text: 'Terminer la course enregistre un DNF pour chaque coureur qui a envoyé au moins une position en direct mais n\'a pas de résultat, avec la distance et le temps de sa dernière position. Ces DNF portent la marque de l\'organisateur. Rien n\'est enregistré pour les coureurs qui n\'ont jamais lancé d\'enregistrement.',
				},
				{
					type: 'p',
					text: 'Un coureur dont le téléphone ou la montre n\'avait pas de réseau à l\'arrivée peut encore envoyer un résultat en attente d\'envoi jusqu\'à 24 heures après la fin de la course, et ce résultat remplace le DNF.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Terminer une course est irréversible. Une fois la course terminée, les appareils des coureurs n\'attendent plus de résultat. Pour courir à nouveau la même occurrence, armez une nouvelle session.',
				},
			],
		},
		{
			heading: 'Annulation',
			blocks: [
				{
					type: 'p',
					text: 'Vous ne pouvez annuler que tant que la course est armée : choisissez **Annuler** à côté de **GO** (**Lancer le Go** dans l\'app mobile), puis **Annuler la course**. Une fois le GO donné, la course ne peut plus qu\'être terminée.',
				},
				{
					type: 'p',
					text: 'L\'annulation n\'enregistre aucun DNF. La page spectateur indique que la course a été annulée par l\'organisateur, et les coureurs voient que la course est terminée.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'L\'annulation est irréversible. Utilisez plutôt **Terminer la course** si des personnes ont réellement couru et que vous voulez leurs résultats.',
				},
			],
		},
		{
			heading: 'Approuver et modifier les résultats',
			blocks: [
				{
					type: 'p',
					text: 'Les résultats se trouvent sur la page de l\'événement sous **Résultats**, avec un classement par parcours. Dans l\'app mobile, chaque résultat a un menu proposant les mêmes actions **Approuver**, **Retirer la validation** et **Modifier**.',
				},
				{
					type: 'list',
					items: [
						'Si l\'approbation automatique était désactivée, les nouveaux résultats affichent **EN ATTENTE** et aucune place. Choisissez **Approuver** pour en publier un. **Retirer la validation** remet un résultat approuvé en attente.',
						'Pour corriger un résultat, choisissez **Modifier**, saisissez un **Temps (h:mm:ss)** et un **Statut** (**Arrivé**, **DNF** ou **DNS**), puis **Enregistrer le résultat**.',
						'Un résultat modifié est marqué **Modifié par l\'organisateur** pour que chacun voie qu\'il a été changé par l\'organisateur. La modification ajuste aussi le temps officiel du coureur.',
						'**Télécharger les résultats (CSV)** exporte les classements.',
					],
				},
			],
		},
	],
	sources: {
		title: '345bfeb73c862a63',
		summary: '68e18b9d83f2ca2d',
		's0.heading': '95b8e6a62cefca57',
		's0.b0': '7b081f765b2e73ec',
		's0.b1': '00aa52e26fec65b0',
		's1.heading': '0f3300a60c9bfa0b',
		's1.b0.i0': '7bdfd19fafd16a95',
		's1.b0.i1': 'b26a53d0fd770ca6',
		's1.b0.i2': 'db729ba4238dbf0f',
		's1.b1': '94ec2fea3c0890dc',
		's1.b2': '9b4a5aa61857cac1',
		's2.heading': 'bcda14674f57c276',
		's2.b0': '933b20b503e29bac',
		's2.b1': '656cb122eaf287fc',
		's2.b2': '65fce2c1be98450f',
		's3.heading': 'c3c4743c28e9dcc0',
		's3.b0.i0': 'aa6bba561bc42aea',
		's3.b0.i1': 'b8ecf8f3f5af1006',
		's3.b0.i2': '9874c56b87143c5f',
		's4.heading': '14dea53ae562634f',
		's4.b0.i0': '4bb0c3a5ddf2738a',
		's4.b0.i1': '9f2d97f9ea8e9cdf',
		's4.b0.i2': 'e63d194b0818af24',
		's4.b1': 'd9f0c880b9265d6c',
		's4.b2': 'eefbd14c075fb596',
		's4.b3': 'b067bfb6142d262b',
		's5.heading': '20d55e8c3373cb09',
		's5.b0': 'df971b2d64e7ef15',
		's5.b1': 'ba1729be79f60bc4',
		's5.b2': 'b10fb4196bd3e2ef',
		's6.heading': '27e65c3d7a252fc5',
		's6.b0': '982210c986719645',
		's6.b1.i0': 'a0e615efe581a71e',
		's6.b1.i1': '0bada1dfb7752ded',
		's6.b1.i2': 'dc555607c15c1ae0',
		's6.b1.i3': '12b5ecdf863972b3',
		's0.b2': '043bfb92b5287252',
	},
};
