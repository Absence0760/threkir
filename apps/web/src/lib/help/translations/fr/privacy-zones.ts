import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'privacy-zones',
	source: 'c3af798bbfeb6e83',
	title: 'Masquer votre domicile avec les zones de confidentialité',
	summary: 'Tracez un cercle autour de votre domicile, de votre travail ou d\'un autre lieu pour masquer à tous sauf vous le début et la fin de vos courses et itinéraires qui s\'y trouvent.',
	sections: [
		{
			heading: 'Ce que fait une zone de confidentialité',
			blocks: [
				{
					type: 'p',
					text: 'Une zone de confidentialité est un cercle sur la carte. Quand une course ou un itinéraire commence ou se termine à l\'intérieur, cette partie du tracé est coupée avant que quiconque d\'autre ne la voie : la ligne semble donc commencer et finir au bord du cercle.',
				},
				{
					type: 'list',
					items: [
						'Elle s\'applique à ce que voient les autres : courses et itinéraires partagés, votre profil public, le fil, les cartes de chaleur et la page de suivi en direct.',
						'Elle s\'applique aux courses déjà enregistrées comme aux nouvelles, car le tracé est rogné chaque fois que quelqu\'un d\'autre le consulte.',
						'Vous voyez toujours votre propre tracé complet, et les fichiers que vous exportez pour vous-même conservent aussi le tracé complet.',
					],
				},
			],
		},
		{
			heading: 'Ajouter une zone sur le web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez [[route:/settings/privacy|Confidentialité et partage]] dans les Paramètres.',
						'Sous **Zones de confidentialité**, sélectionnez **Ajouter une zone**.',
						'Cliquez sur la carte à l\'endroit où la zone doit être centrée, ou sélectionnez **Utiliser ma position actuelle**, puis faites glisser le repère pour l\'ajuster.',
						'Réglez le **Rayon**. Tout ce qui se trouve dans le cercle rouge est masqué des partages publics.',
						'Sélectionnez **Ajouter la zone**. La zone est enregistrée immédiatement.',
					],
				},
				{
					type: 'p',
					text: 'Pour supprimer une zone, sélectionnez **Supprimer** à côté d\'elle et confirmez. Supprimer une zone rend ce secteur à nouveau visible sur les partages publics.',
				},
			],
		},
		{
			heading: 'Ajouter une zone dans l\'app mobile',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez l\'onglet **Vous**, puis **Préférences**, et sous **Confidentialité et partage**, touchez **Zones de confidentialité**.',
						'Touchez la carte pour placer une zone. Utilisez **Rechercher des lieux…** ou **Me localiser** pour déplacer d\'abord la carte.',
						'Ajustez le curseur **Rayon**.',
						'Touchez **Enregistrer**. Rien ne change tant que vous n\'avez pas enregistré.',
					],
				},
				{
					type: 'p',
					text: 'Pour supprimer une zone, touchez son repère et confirmez, ou utilisez **Tout effacer** pour retirer toutes les zones d\'un coup. Touchez ensuite **Enregistrer** ; supprimer une zone rend ce secteur à nouveau visible sur les partages publics.',
				},
			],
		},
		{
			heading: 'Bien choisir sa zone',
			blocks: [
				{
					type: 'list',
					items: [
						'Centrez la zone près de votre porte d\'entrée plutôt que pile dessus, pour que le bord du cercle ne pointe pas droit vers votre maison.',
						'Faites-la assez grande pour couvrir quelques rues. Un tout petit cercle peut encore trahir votre domicile.',
						'Ajoutez-en une pour chaque lieu d\'où vous partez régulièrement, comme votre travail ou la maison d\'un ami.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Les zones ne rognent que la ligne sur la carte. Le titre, la description et les photos d\'une course s\'affichent tels que vous les avez écrits : n\'y mettez donc pas d\'adresse.',
				},
			],
		},
	],
};
