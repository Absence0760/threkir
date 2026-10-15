import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'private-profile-and-follow-requests',
	title: 'Rendre votre profil privé et accepter des abonnés',
	summary: 'Activez un profil privé pour que seuls les abonnés que vous acceptez voient vos courses, puis acceptez ou refusez les demandes d\'abonnement à mesure qu\'elles arrivent.',
	sections: [
		{
			heading: 'Ce que masque un profil privé',
			blocks: [
				{
					type: 'p',
					text: 'Avec un profil privé, seuls les abonnés que vous avez acceptés voient vos courses et vos autres activités, ainsi que les listes de vos abonnés et de vos abonnements. Les autres voient votre nom, votre photo et vos nombres d\'abonnés, avec **Ce profil est privé** à la place de vos courses.',
				},
				{
					type: 'list',
					items: [
						'On peut toujours vous trouver par votre nom et demander à s\'abonner. Pour ne plus apparaître non plus dans la recherche par nom, désactivez **M\'afficher dans la recherche par nom** sur la même page.',
						'Les personnes déjà abonnées quand vous l\'activez restent abonnées.',
						'Les itinéraires, les résultats d\'événements et les badges gardent leur propre visibilité, car chacun est partagé séparément.',
						'Un lien en direct que vous envoyez pendant une course, y compris le lien d\'une alerte de sécurité, fonctionne toujours pour les personnes à qui vous l\'avez envoyé.',
					],
				},
			],
		},
		{
			heading: 'L\'activer',
			blocks: [
				{
					type: 'steps',
					items: [
						'Sur le web, ouvrez [[route:/settings/privacy|Confidentialité et partage]] dans les Paramètres et cochez **Profil privé** sous **Être trouvé**.',
						'Dans l\'app mobile, ouvrez **Préférences** dans l\'onglet **Vous** et activez **Profil privé** sous **Confidentialité et partage**.',
					],
				},
				{
					type: 'p',
					text: 'La modification est enregistrée immédiatement.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Le désactiver accepte toutes les demandes encore en attente : ces personnes deviennent aussitôt vos abonnés.',
				},
			],
		},
		{
			heading: 'Accepter ou refuser les demandes',
			blocks: [
				{
					type: 'p',
					text: 'Quand quelqu\'un demande à s\'abonner, vous recevez une notification. Les demandes d\'abonnement comptent parmi les notifications importantes : par défaut, elles vous sont aussi envoyées par e-mail et en push.',
				},
				{
					type: 'steps',
					items: [
						'Ouvrez la notification. Vous pouvez aussi sélectionner **Voir les demandes d\'abonnement** sous **Profil privé** sur le web, ou toucher **Demandes d\'abonnement** sous **Profil privé** dans l\'app mobile.',
						'Choisissez **Accepter** pour que cette personne voie votre profil, ou **Refuser** pour décliner la demande. Elle n\'est pas prévenue en cas de refus.',
					],
				},
			],
		},
		{
			heading: 'Suivre quelqu\'un qui a un profil privé',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez son profil et choisissez **Demander à s\'abonner**.',
						'Le bouton affiche **Demande envoyée** pendant l\'attente. Choisissez-le de nouveau pour retirer la demande.',
						'Une fois la demande acceptée, le bouton affiche **Abonné** et ses courses apparaissent.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si vous vous désabonnez d\'une personne au profil privé, vous devez refaire une demande pour voir ses courses.',
				},
			],
		},
	],
	sources: {
		title: '55db0776dec72032',
		summary: 'e6bdb709c41db3db',
		's0.heading': '7237eeb5591555f6',
		's0.b0': '7c2c985869ef044e',
		's0.b1.i0': '46be0ce6681dea88',
		's0.b1.i1': 'a724eac62d2e2309',
		's0.b1.i2': 'ab64bd2163f3b938',
		's0.b1.i3': '3b0697b82ce30a11',
		's1.heading': 'e679ca0953315c31',
		's1.b0.i0': '8f81f66ef4f33b7f',
		's1.b0.i1': 'a2257970d4c18f57',
		's1.b1': '0a095b7bf566bcfd',
		's1.b2': 'ad288ebf5f9c8856',
		's2.heading': '93f13a5ed9bf1a93',
		's2.b0': 'd2a27163d9554bb2',
		's2.b1.i0': '2ed84578bbbb7b5f',
		's2.b1.i1': '6d2ff83c41b08bdc',
		's3.heading': '185850fe604d3b78',
		's3.b0.i0': 'd39f871565375e15',
		's3.b0.i1': 'd9de093774b97d75',
		's3.b0.i2': 'e44b708377c7377a',
		's3.b1': '6f8889c46cf20f3c',
	},
};
