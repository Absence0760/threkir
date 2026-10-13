import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'refund-policies',
	source: 'be8b580dfc980abf',
	title: 'Politiques de remboursement et annulation de votre inscription',
	summary: 'Le fonctionnement des trois politiques de remboursement, comment un participant annule une inscription payée et ce qu\'il voit lorsqu\'il le fait.',
	sections: [
		{
			heading: 'Avant de commencer',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'L\'inscription payante n\'est pas encore active. Elle exige que le compte Stripe de l\'organisateur soit connecté et que la plateforme ait activé les paiements. D\'ici là, aucun événement ne peut être payant : il n\'y a donc rien à rembourser.',
				},
			],
		},
		{
			heading: 'Les trois politiques',
			blocks: [
				{
					type: 'p',
					text: 'L\'organisateur choisit une **Politique de remboursement** en créant un événement payant. Elle détermine ce que récupère une personne si c\'est *elle* qui annule, et elle est affichée sur la page de l\'événement avant tout paiement.',
				},
				{
					type: 'list',
					items: [
						'**Remboursement intégral jusqu’à l’heure de début** : affichée aux participants comme **Annulation gratuite jusqu\'au début de l\'événement**.',
						'**Remboursement intégral jusqu’à 24 h avant** : affichée comme **Annulation gratuite jusqu\'à 24 heures avant le début**. C\'est la politique par défaut.',
						'**Aucun remboursement** : affichée comme **Aucun remboursement en cas d\'annulation**.',
					],
				},
				{
					type: 'p',
					text: 'Un remboursement, c\'est tout ou rien : dans le délai, vous récupérez la totalité du prix ; hors délai, vous ne récupérez rien. Le délai se calcule par rapport au début de l\'occurrence à laquelle vous êtes inscrit.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'La politique ne couvre que l\'annulation par un participant. Si l\'organisateur annule un cours, tous ceux qui ont payé sont remboursés intégralement, quelle que soit la politique : voir [[guide:cancel-a-class|Annuler un cours]].',
				},
			],
		},
		{
			heading: 'Annuler votre propre inscription',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez l\'événement sur le web. Là où s\'affiche **Vous êtes inscrit**, appuyez sur **Annuler l’inscription**.',
						'Lisez la boîte de dialogue. Dans le délai de remboursement, elle indique que vous serez remboursé sur votre moyen de paiement d\'origine et que votre place se libère pour une personne de la liste d\'attente.',
						'Appuyez sur **Annuler l’inscription** pour confirmer, ou sur **Garder ma place** pour renoncer.',
					],
				},
				{
					type: 'p',
					text: 'Une fois l\'opération effectuée, vous voyez **Remboursement lancé — il peut prendre quelques jours à apparaître. Votre place a été libérée.** Tant que votre banque ne l\'a pas confirmé, la page affiche **Remboursement en cours**.',
				},
				{
					type: 'p',
					text: 'Si vous avez quitté le paiement avant de payer, le même bouton annule plutôt l\'inscription en attente : votre place réservée est libérée et aucun paiement n\'est prélevé.',
				},
			],
		},
		{
			heading: 'Hors du délai de remboursement',
			blocks: [
				{
					type: 'p',
					text: 'Une fois le délai passé, ou pour un événement **Aucun remboursement**, l\'app ne peut pas annuler votre inscription à votre place. La boîte de dialogue vous prévient avant que vous essayiez, vous gardez votre place, et si vous continuez vous verrez **Cette inscription a dépassé le délai de remboursement. Contactez l’organisateur pour annuler.**',
				},
			],
		},
		{
			heading: 'Si un remboursement n\'arrive pas',
			blocks: [
				{
					type: 'p',
					text: 'Il arrive qu\'une banque renvoie un remboursement. La page de l\'événement affiche alors **Votre remboursement ne vous est pas parvenu** et une notification indique **Un remboursement n’a pas abouti — nous vous recontacterons**. Vous n\'avez pas besoin de payer à nouveau : utilisez **Contacter la facturation** et la somme vous sera restituée par un autre moyen.',
				},
			],
		},
	],
};
