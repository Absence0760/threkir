import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'invite-members-and-roles',
	source: '1140e414e73d9132',
	title: 'Inviter des membres et leur attribuer des rôles',
	summary: 'Partagez un lien d\'invitation, approuvez les demandes d\'adhésion et attribuez à des membres de confiance le rôle d\'admin, d\'organisateur d\'événements ou de directeur de course.',
	sections: [
		{
			heading: 'Comment rejoindre un club',
			blocks: [
				{
					type: 'p',
					text: 'La façon de rejoindre dépend de la politique d\'adhésion du club, que vous avez choisie à sa création et que vous pouvez modifier avec **Modifier le club** sur le web.',
				},
				{
					type: 'list',
					items: [
						'**Tout le monde peut rejoindre** : les gens sélectionnent **Rejoindre le club** sur la page du club et en font partie immédiatement.',
						'**Approbation requise** : les gens sélectionnent **Demander à rejoindre** et patientent dans une file jusqu\'à ce qu\'un admin les approuve.',
						'**Sur invitation uniquement** : il faut un lien d\'invitation fourni par un admin.',
					],
				},
			],
		},
		{
			heading: 'Partager un lien d\'invitation',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez votre club sur le web. Quand le club est **Sur invitation uniquement**, les admins voient un panneau **Lien d\'invitation** sur la page du club.',
						'Sélectionnez **Générer un lien d\'invitation** la première fois, puis **Copier** pour placer le lien dans votre presse-papiers.',
						'Envoyez le lien comme vous le souhaitez. Toute personne qui l\'ouvre et se connecte rejoint le club en tant que membre.',
					],
				},
				{
					type: 'p',
					text: 'Si un lien a circulé plus loin que prévu, sélectionnez **Renouveler**. Un nouveau lien est créé et l\'ancien cesse immédiatement de fonctionner.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Un lien d\'invitation fait entrer directement : il contourne la file d\'approbation, alors ne le partagez qu\'avec des personnes que vous êtes prêt à accepter. Si le club exige la reconnaissance des risques liés à l\'activité, le lien la demande avant de laisser entrer qui que ce soit.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Dans l\'app mobile, un membre peut aussi toucher **Rejoindre avec un code d\'invitation** dans l\'onglet **Clubs** de **Social** et coller le lien entier ou seulement le code après /clubs/join/. Ouvrir le lien dans le navigateur du téléphone fonctionne aussi.',
				},
			],
		},
		{
			heading: 'Approuver ou refuser les demandes d\'adhésion',
			blocks: [
				{
					type: 'p',
					text: 'Quand le club exige une approbation, les admins voient **Demandes en attente** avec leur nombre à côté.',
				},
				{
					type: 'list',
					items: [
						'Sur le web, sélectionnez **Approuver** ou **Refuser** sur chaque demande, ou **Tout approuver** quand plusieurs sont en attente. Un refus vous demande d\'abord de confirmer.',
						'Dans l\'app mobile, ouvrez l\'onglet **Membres** du club et touchez **Approuver** ou **Refuser** sur chaque demande.',
					],
				},
			],
		},
		{
			heading: 'Attribuer un rôle aux membres',
			blocks: [
				{
					type: 'p',
					text: 'Chaque club a un seul **Propriétaire**, la personne qui l\'a créé. Les autres peuvent avoir l\'un de ces rôles :',
				},
				{
					type: 'list',
					items: [
						'**Admin** : modifie les paramètres du club, gère les membres et leurs rôles, organise les événements et les courses, et approuve les résultats.',
						'**Organisateur d\'événements** : crée, modifie et supprime des événements et ajoute des participants, sans accès aux paramètres ni aux membres du club.',
						'**Directeur de course** : arme, lance et termine les courses, et approuve ou refuse les résultats.',
						'**Membre** : publie des réponses, indique sa participation aux événements et soumet ses propres résultats de course.',
					],
				},
				{
					type: 'steps',
					items: [
						'Ouvrez votre club sur le web et choisissez l\'onglet **Membres**.',
						'Utilisez le menu de rôle à côté d\'un membre pour choisir son nouveau rôle. La modification est enregistrée immédiatement.',
						'Pour retirer quelqu\'un du club, utilisez le bouton de retrait à côté de son nom et confirmez.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'La modification des rôles et le retrait de membres ne se font pour l\'instant que sur le web. L\'onglet **Membres** de l\'app mobile affiche le nombre de membres et les demandes en attente, pas la liste complète.',
				},
			],
		},
	],
};
