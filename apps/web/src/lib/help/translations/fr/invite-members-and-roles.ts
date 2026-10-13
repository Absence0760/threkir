import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'invite-members-and-roles',
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
	sources: {
		title: '7a795179c19e9ede',
		summary: '6bd8f063f9b47e9c',
		's0.heading': 'a0b11759509dec45',
		's0.b0': '6373b2a85a1609f6',
		's0.b1.i0': 'ee27e4b5847787d3',
		's0.b1.i1': 'b3ca923e10bea1a6',
		's0.b1.i2': '43f232607a69a9eb',
		's1.heading': 'ff3fad2f072540f7',
		's1.b0.i0': '53bc4c42c338a50b',
		's1.b0.i1': '527bae1b53082d53',
		's1.b0.i2': '7717031f30823ba7',
		's1.b1': '71a8c58fdf04e4c7',
		's1.b2': 'ac04b52b16128c47',
		's1.b3': '95001612b9e89408',
		's2.heading': 'ac0d31b6960aec87',
		's2.b0': '5e020c1365ade658',
		's2.b1.i0': '001fdb020367ef82',
		's2.b1.i1': '8a13349f6280affe',
		's3.heading': '5ae9577e9c45959a',
		's3.b0': '6b88528b0352a4ca',
		's3.b1.i0': '4a654fadcb92a4e9',
		's3.b1.i1': '4fb82402d20e5ae6',
		's3.b1.i2': '99c1319e71b4efe7',
		's3.b1.i3': 'd2c28cf99bce668b',
		's3.b2.i0': '8552b807ede6b519',
		's3.b2.i1': '12d66025f3fdd53b',
		's3.b2.i2': '2bc7dca0194195b4',
		's3.b3': '2dbf13356f8d50fe',
	},
};
