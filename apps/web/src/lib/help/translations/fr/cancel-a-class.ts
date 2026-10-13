import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'cancel-a-class',
	source: '8ee15ec25324129c',
	title: 'Annuler un cours et rembourser tous ceux qui ont payé',
	summary: 'Annulez une occurrence d\'un cours récurrent : chaque personne qui l\'a payée est remboursée intégralement et automatiquement, avec une relance toutes les heures et un recours Rembourser maintenant.',
	sections: [
		{
			heading: 'Avant de commencer',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Les cours payants ne sont pas encore actifs : il faut que le compte Stripe de l\'organisateur soit connecté et que la plateforme ait activé les paiements. Si les paiements ne sont pas disponibles quand vous essayez d\'annuler une occurrence qui a des inscriptions payées, vous verrez **Cette occurrence a des inscriptions payées et les paiements ne sont pas disponibles pour le moment : elle ne peut donc pas encore être annulée. Rien n’a été modifié.** Le cours est maintenu, pour que personne ne se retrouve avec un paiement pour un cours qui n\'a pas lieu.',
				},
				{
					type: 'p',
					text: 'L\'annulation est réservée aux admins et aux organisateurs d\'événements du club, et elle se fait sur le web. Les cours gratuits s\'annulent de la même façon, simplement sans remboursement.',
				},
			],
		},
		{
			heading: 'Annuler une occurrence',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez le cours sur le web. S\'il se répète, utilisez **Choisir une occurrence** pour sélectionner la date que vous annulez.',
						'Appuyez sur **Annuler cette occurrence**.',
						'La boîte de dialogue explique que seule cette occurrence est annulée et que le reste de la série n\'est pas touché. Pour un cours payant, elle ajoute : **Toutes les personnes inscrites à cette occurrence sont remboursées intégralement, quelle que soit la politique de remboursement.**',
						'Ajoutez si vous le souhaitez un **Motif (facultatif)**, puis appuyez de nouveau sur **Annuler cette occurrence** pour confirmer, ou sur **Conserver** pour renoncer.',
					],
				},
				{
					type: 'p',
					text: 'Une fois l\'opération terminée, vous voyez combien de personnes sont remboursées, par exemple *Occurrence annulée. 8 personnes inscrites sont remboursées intégralement.* Toute personne en cours de paiement voit sa place réservée libérée et n\'est pas débitée. Personne n\'est transféré de la liste d\'attente vers un cours annulé.',
				},
			],
		},
		{
			heading: 'Ce que vos participants apprennent',
			blocks: [
				{
					type: 'p',
					text: 'Toutes les personnes ayant répondu pour cette occurrence (participe, peut-être ou en liste d\'attente) sont prévenues. Celles qui ont payé reçoivent une notification du type *Une occurrence de « Tuesday Reformer » a été annulée — ton paiement est en cours de remboursement*, et le même texte part par e-mail ou par notification push à celles qui les reçoivent. Le message dit *en cours de* remboursement parce que le remboursement est lancé à ce moment-là et peut mettre quelques jours à arriver sur leur compte bancaire.',
				},
			],
		},
		{
			heading: 'Si un remboursement échoue',
			blocks: [
				{
					type: 'p',
					text: 'L\'occurrence reste annulée même si Stripe refuse un remboursement. Un message vous indique combien de remboursements n\'ont pas pu être lancés, et la page du cours affiche une carte **Remboursements des occurrences annulées** qui liste, pour chaque date annulée, qui n\'a pas encore été remboursé, quels remboursements sont en cours et ceux que la banque a renvoyés.',
				},
				{
					type: 'list',
					items: [
						'L\'app relance automatiquement, une fois par heure, chaque remboursement encore dû sur un cours annulé.',
						'Vous n\'êtes pas obligé d\'attendre : appuyez sur **Rembourser maintenant** à côté de l\'occurrence pour réessayer tout de suite. Personne n\'est jamais remboursé deux fois.',
						'Un remboursement renvoyé par la banque ne peut pas être relancé de cette façon ; il est restitué à la personne par un autre moyen.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ne remboursez pas les gens à la main depuis un tableau de bord Stripe. Un remboursement fait là-bas peut ne pas annuler votre versement ni les frais de plateforme, et l\'app risque ensuite de rembourser le reste en plus. Utilisez plutôt **Rembourser maintenant**.',
				},
			],
		},
		{
			heading: 'Cours ponctuels et séries entières',
			blocks: [
				{
					type: 'p',
					text: '**Annuler cette occurrence** n\'est proposé que pour un cours récurrent. Il n\'existe pas de bouton unique pour annuler toute une série : annulez chaque occurrence à venir qui a des inscriptions.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: '**Supprimer l\'événement** n\'est pas une annulation. Cela supprime l\'événement et toutes ses occurrences, et ne rembourse personne parmi ceux qui ont payé. Ne supprimez pas un cours payant qui a encore des inscriptions.',
				},
				{
					type: 'p',
					text: 'Vous avez changé d\'avis ? **Rétablir cette occurrence** remet une date annulée au calendrier, mais les remboursements déjà effectués ne sont pas annulés : les participants devront donc se réinscrire.',
				},
			],
		},
	],
};
