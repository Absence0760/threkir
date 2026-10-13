import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'waitlist-and-claim-window',
	source: 'd01f2b1f78e23484',
	title: 'Listes d\'attente et délai de 12 heures pour réclamer une place',
	summary: 'Comment rejoindre un cours complet, comment une place libérée vous est réservée 12 heures pour un cours payant, et ce qui se passe si vous ne la réclamez pas.',
	sections: [
		{
			heading: 'Cours gratuits : vous êtes inscrit automatiquement',
			blocks: [
				{
					type: 'p',
					text: 'Quand un cours gratuit avec une **Capacité** est complet, appuyer sur **Je participe** vous place sur la liste d\'attente et votre réponse affiche **En liste d\'attente**. Quand quelqu\'un se désiste, la première personne de la liste d\'attente passe automatiquement à **Participe** ; il n\'y a rien à réclamer. Cela fonctionne sur le web et dans l\'app mobile.',
				},
			],
		},
		{
			heading: 'Cours payants : une place est réservée, puis vous payez',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Les cours payants ne sont pas encore actifs : il faut que le compte Stripe de l\'organisateur soit connecté et que la plateforme ait activé les paiements. Tout ce qui figure dans cette section s\'applique une fois que c\'est le cas.',
				},
				{
					type: 'p',
					text: 'Personne n\'est débité simplement pour être sur une liste d\'attente. Quand une place se libère, elle vous est proposée et vous payez pour l\'obtenir.',
				},
				{
					type: 'steps',
					items: [
						'Pour un cours payant complet, la page affiche **Complet**. Tant que les ventes sont ouvertes, appuyez sur **Rejoindre la liste d’attente**. Vous verrez **Vous êtes sur la liste d’attente. Si une place se libère, nous vous la réservons et vous prévenons.**',
						'Quand une place se libère et que vous êtes le premier de la file, vous recevez une notification : *Une place s’est libérée pour « Tuesday Reformer » et vous est réservée — payez pour l’obtenir*.',
						'Ouvrez le cours sur le web. Il indique quand votre réservation prend fin, par exemple *Une place vous est réservée jusqu’à mardi 6 mai à 18:00. Payez pour l’obtenir, sinon elle revient à la personne suivante sur la liste d’attente.*',
						'Appuyez sur le bouton de réclamation (il affiche *Obtenir ma place* avec le prix) puis finalisez le paiement. Une fois le paiement effectué, vous êtes inscrit comme tout le monde.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'La réclamation se fait sur le web. L\'app mobile affiche la notification et ouvre le cours, mais n\'a pas encore de paiement : ouvrez donc le cours dans un navigateur pour payer.',
				},
			],
		},
		{
			heading: 'Durée de la réservation',
			blocks: [
				{
					type: 'list',
					items: [
						'Vous avez 12 heures pour réclamer la place, assez pour que personne ne la perde parce qu\'il dormait.',
						'La réservation est écourtée quand les ventes du cours se terminent (l\'heure de clôture des ventes fixée par l\'organisateur avant le début). Aucune place n\'est proposée après la clôture des ventes, car personne ne pourrait la payer.',
						'Tant que votre place est réservée, personne d\'autre ne peut l\'acheter, même si le cours leur paraît complet.',
						'Si vous êtes en plein paiement quand le temps est écoulé, la réservation est maintenue tant que ce paiement reste ouvert.',
					],
				},
			],
		},
		{
			heading: 'Si vous ne la réclamez pas',
			blocks: [
				{
					type: 'p',
					text: 'Quand la réservation expire, la place est proposée à la personne suivante sur la liste d\'attente et vous quittez la liste d\'attente. Si vous voulez toujours participer, appuyez de nouveau sur **Rejoindre la liste d’attente** ; vous passez en fin de file.',
				},
				{
					type: 'p',
					text: 'Vous avez changé d\'avis pendant que vous attendez encore ? Appuyez sur **Quitter la liste d’attente**. L\'app vous prévient que vous perdrez votre place dans la file ; si vous la rejoignez plus tard, vous passez en fin de file. Si une place vous est déjà réservée et que vous n\'en voulez pas, laissez simplement la réservation expirer.',
				},
			],
		},
		{
			heading: 'Pour les organisateurs',
			blocks: [
				{
					type: 'list',
					items: [
						'La liste d\'attente se gère toute seule. Définissez une **Capacité** pour le cours et le reste se fait automatiquement ; le délai de 12 heures ne peut pas être modifié cours par cours.',
						'Une place réservée compte dans votre capacité : vous n\'avez donc jamais plus de personnes que de tapis.',
						'Si quelqu\'un annule avec remboursement, sa place revient à la liste d\'attente. Si vous annulez une occurrence, personne n\'y est transféré depuis la liste d\'attente : voir [[guide:cancel-a-class|Annuler un cours]].',
					],
				},
			],
		},
	],
};
