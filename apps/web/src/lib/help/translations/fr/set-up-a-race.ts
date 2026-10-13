import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'set-up-a-race',
	source: '007da6d05532b4cb',
	title: 'Organiser une course',
	summary: 'Créez un événement de club avec un ou plusieurs parcours pour que les coureurs choisissent une distance, soient chronométrés en direct et figurent au classement de leur parcours.',
	sections: [
		{
			heading: 'Avant de commencer',
			blocks: [
				{
					type: 'p',
					text: 'Une course est un événement de club ordinaire auquel sont rattachés des parcours. Les propriétaires, les admins et les organisateurs d\'événements du club peuvent créer des événements. Gérer la course le jour J (armer, GO, terminer) nécessite un propriétaire, un admin ou un **Directeur de course** — voir [[guide:race-day-for-hosts|Le jour de la course, côté organisateur]].',
				},
				{
					type: 'p',
					text: 'Les parcours se créent sur le web. L\'app mobile peut créer un événement simple, mais elle n\'a pas d\'éditeur de parcours : ajoutez ou modifiez les parcours depuis un navigateur.',
				},
			],
		},
		{
			heading: 'Créer l\'événement',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez votre club et choisissez **Nouvel événement**.',
						'Sous **Type d\'événement**, choisissez **Sortie en groupe** (ou **Vélo**). Les cours et les événements sociaux n\'ont ni itinéraire, ni distance, ni contrôle de course, ni résultats.',
						'Donnez-lui un **Titre** et une **Date**. Ne définissez une répétition que si la course a vraiment lieu régulièrement ; chaque occurrence est courue séparément.',
						'Choisissez un **Parcours** et renseignez la **Distance**. Ensemble, ils forment votre *parcours principal*.',
						'Saisissez éventuellement un **Nom du parcours principal** sous **Parcours de la course** (par exemple « Semi-marathon »). Si vous le laissez vide, le nom de l\'itinéraire est utilisé.',
						'Choisissez **Créer l\'événement**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'La ligne d\'arrivée où les coureurs sont chronométrés est le dernier point de l\'itinéraire du parcours. Tracez l\'itinéraire pour qu\'il se termine exactement à l\'emplacement de votre arche d\'arrivée.',
				},
			],
		},
		{
			heading: 'Ajouter d\'autres parcours',
			blocks: [
				{
					type: 'p',
					text: 'Plusieurs distances le même jour ? Ajoutez chaque distance supplémentaire comme un parcours distinct. Chaque parcours a son propre classement.',
				},
				{
					type: 'steps',
					items: [
						'Dans l\'éditeur d\'événement, repérez **Parcours de la course** et choisissez **Ajouter un parcours**.',
						'Donnez-lui un **Nom du parcours**, choisissez son **Itinéraire** et saisissez sa distance.',
						'Utilisez les flèches haut et bas pour réordonner les parcours, ou supprimez-en un dont vous n\'avez plus besoin.',
						'Enregistrez l\'événement.',
					],
				},
				{
					type: 'list',
					items: [
						'Chaque parcours doit avoir un nom, et deux parcours ne peuvent pas porter le même.',
						'Un parcours sans itinéraire n\'a pas de point d\'arrivée : l\'arrivée de ses coureurs n\'est donc pas automatique, et ils terminent à la main depuis leur appareil.',
						'Un parcours sans distance ne permet pas de vérifier qu\'un coureur en a couvert la majeure partie : ses coureurs terminent donc aussi à la main.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Rattacher un itinéraire rend son point d\'arrivée visible par toute personne qui peut voir l\'événement, même si l\'itinéraire lui-même est privé. Vous ne pouvez rattacher que des itinéraires que vous êtes autorisé à voir.',
				},
			],
		},
		{
			heading: 'Ce que voient les coureurs',
			blocks: [
				{
					type: 'list',
					items: [
						'Sur la page de l\'événement, les coureurs voient les parcours. S\'il y en a plusieurs, ils doivent en choisir un dans **Ton parcours** pour que **Je participe** fonctionne ; sinon, ils voient « Choisis d\'abord ton parcours. »',
						'Dans l\'app mobile, toucher **Je viens** sur une course à plusieurs parcours leur demande **Choisissez votre parcours**, et ils peuvent utiliser **Changer de parcours** plus tard.',
						'Avec un seul parcours, personne n\'a rien à choisir.',
						'Les inscriptions payantes ne demandent pas encore de parcours. Un coureur qui a payé en choisit un ensuite depuis le même menu **Ton parcours**.',
					],
				},
				{
					type: 'p',
					text: 'Le côté coureur est expliqué dans [[guide:racing-in-a-race|Participer à une course]].',
				},
			],
		},
		{
			heading: 'Approuver les résultats automatiquement',
			blocks: [
				{
					type: 'p',
					text: 'Juste avant d\'armer la course, vous choisissez si les résultats vont directement au classement. **Approuver automatiquement les résultats soumis** est coché par défaut. Décochez-le si vous voulez vérifier chaque résultat d\'abord ; chacun s\'affiche alors **EN ATTENTE** jusqu\'à ce que vous l\'approuviez.',
				},
			],
		},
		{
			heading: 'Partager le lien spectateur',
			blocks: [
				{
					type: 'p',
					text: 'Chaque occurrence de course a une page en direct avec une carte et des classements. Sur la page de l\'événement, la carte de contrôle de course comporte un lien **Vue spectateur** qui l\'ouvre dans un nouvel onglet. Copiez cette adresse et partagez-la avec votre famille, vos amis et le canal de votre course.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Pour un événement **Réservé aux membres**, seuls les membres du club peuvent voir l\'événement : la page spectateur ne fonctionnera donc pas pour les personnes extérieures au club.',
				},
				{
					type: 'p',
					text: 'Ce que voient les spectateurs est expliqué dans [[guide:follow-a-race-live|Suivre une course en direct]].',
				},
			],
		},
	],
};
