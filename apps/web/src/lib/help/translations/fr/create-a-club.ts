import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'create-a-club',
	source: 'eb2c9f65431381b4',
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
	],
};
