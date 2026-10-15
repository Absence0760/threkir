import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'create-a-club',
	title: 'Créer un club',
	summary: 'Lancez un club pour votre groupe de course, choisissez qui peut le trouver et comment le rejoindre, puis publiez votre premier événement.',
	sections: [
		{
			heading: 'Sur le web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez [[route:/social|Social]] et choisissez l\'onglet **Clubs**.',
						'Sélectionnez **Créer un club**.',
						'Renseignez le **Nom**. Les membres recherchent le club par ce nom, et l\'adresse web du club en est tirée lors de sa création. Renommer le club plus tard ne change pas cette adresse.',
						'Ajoutez une **Description** et un **Lieu** si vous le souhaitez. Les deux sont facultatifs, mais une ville et un pays dans **Lieu** aident les coureurs à proximité à vous trouver quand ils cherchent dans leur région.',
						'Choisissez une **Visibilité** : les clubs **Public** apparaissent dans **Parcourir**, tandis que les clubs **Privé** sont masqués et ne peuvent être rejoints que par un lien d\'invitation.',
						'Sous **Qui peut rejoindre ?**, choisissez **Tout le monde peut rejoindre**, **Approbation requise** ou **Sur invitation uniquement**.',
						'Cochez **Exiger une reconnaissance des risques liés à l\'activité pour rejoindre** si vous voulez que chaque nouveau membre confirme qu\'il comprend les risques des sorties en groupe. Ce réglage ne peut être défini que maintenant, pendant la création du club.',
						'Sélectionnez **Créer le club**. Vous arrivez sur la page du nouveau club, dont vous êtes le propriétaire.',
					],
				},
			],
		},
		{
			heading: 'Dans l\'app mobile',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez l\'onglet **Social** et choisissez **Clubs**.',
						'Touchez **Nouveau club**.',
						'Saisissez un **Nom** et, si vous le souhaitez, une **Description (facultatif)** et un **Lieu (facultatif)**.',
						'Choisissez **Public** ou **Privé**, puis une **Politique d\'adhésion** : **Ouvert — tout le monde rejoint**, **Demande — les admins approuvent** ou **Sur invitation**.',
						'Touchez **Créer**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'La reconnaissance des risques liés à l\'activité ainsi que le site web et les liens sociaux du club ne peuvent être définis que sur le web.',
				},
			],
		},
		{
			heading: 'Après la création',
			blocks: [
				{
					type: 'p',
					text: 'La page de votre club comporte les onglets **Fil**, **Événements**, **Itinéraires**, **Modèles**, **Photos** et **Membres**. En tant que propriétaire, vous pouvez publier des actualités dans le fil, ajouter des événements et gérer les membres.',
				},
				{
					type: 'list',
					items: [
						'Pour modifier plus tard le nom, la description, la visibilité, la politique d\'adhésion ou les liens, ouvrez le club sur le web et sélectionnez **Modifier le club**.',
						'Pour ajouter votre première sortie en groupe, sélectionnez **Nouvel événement** sur le web, ou touchez **Créer un événement** dans l\'onglet **Événements** de l\'app mobile.',
						'Pour faire venir du monde, voir [[guide:invite-members-and-roles|Inviter des membres et leur attribuer des rôles]].',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Supprimer un club supprime tous ses événements, publications et membres pour tout le monde, et c\'est irréversible.',
				},
			],
		},
		{
			heading: 'Importer un club depuis Strava',
			blocks: [
				{
					type: 'p',
					text: 'Si votre compte Strava est connecté, ouvrez [[route:/social|Social]] sur le web, choisissez **Clubs** puis **Mes clubs**. Sous **Tes clubs Strava**, vous voyez les clubs Strava dont vous êtes membre. Vous seul voyez cette liste.',
				},
				{
					type: 'list',
					items: [
						'**Créer sur Threkir** ouvre le formulaire d\'un nouveau club avec son nom et son lieu déjà remplis, et lie les deux dès que vous créez le club.',
						'**Lier à mon club** le relie à un club que vous gérez déjà ici : choisissez-le sous **Lequel de tes clubs est-ce ?** puis sélectionnez **Lier**.',
						'**Délier** supprime le lien. Aucun des deux clubs n\'est modifié.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Seul un administrateur du club sur Strava peut le lier, et seulement à un club dont il est propriétaire ou administrateur ici. Si la section n\'apparaît pas, connectez d\'abord Strava dans [[route:/settings/integrations|Intégrations]] dans les Paramètres.',
				},
			],
		},
	],
	sources: {
		title: 'ff916040a4a088ae',
		summary: '90e58c1ce029b9f8',
		's0.heading': '1e1b85a2667ca4d5',
		's0.b0.i0': '81704e449355f8cb',
		's0.b0.i1': 'acfe56320dd5fa86',
		's0.b0.i2': '8f5ed6e368636764',
		's0.b0.i3': '0b33c70ca105f651',
		's0.b0.i4': 'ac21a20e9c83b3b8',
		's0.b0.i5': '7d3a8a5850778a1a',
		's0.b0.i6': '8a20a1b7087f8a35',
		's0.b0.i7': '019cb8b4c6074fbe',
		's1.heading': 'f21eaef94c685b5c',
		's1.b0.i0': 'ecd88baa3a8b6dfe',
		's1.b0.i1': 'fe76ba21da4f039b',
		's1.b0.i2': '2cc7185287318c16',
		's1.b0.i3': '4bd544b513ee23e9',
		's1.b0.i4': '42d0b5b43ab9db8b',
		's1.b1': '8cc57f936798f492',
		's2.heading': '6620415f4bf77118',
		's2.b0': 'a1a749aa3fcf7a85',
		's2.b1.i0': 'a21817fe350e546b',
		's2.b1.i1': '102566e11462e84f',
		's2.b1.i2': '83bc170018336efe',
		's2.b2': 'eb88a7323310e67e',
		's3.heading': '78e0de8618ff020a',
		's3.b0': '728fa56591eb888d',
		's3.b1.i0': '57a98843d18952a0',
		's3.b1.i1': '6866a373a29d0bdb',
		's3.b1.i2': 'afe5b3477e772c36',
		's3.b2': '0c5f0a91de4775f1',
	},
};
