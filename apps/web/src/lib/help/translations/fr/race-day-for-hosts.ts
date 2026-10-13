import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-day-for-hosts',
	source: 'a0030f79feb5cc1b',
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
};
