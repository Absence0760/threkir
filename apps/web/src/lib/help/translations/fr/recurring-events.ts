import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'recurring-events',
	source: 'd308eeb2564d2425',
	title: 'Créer un événement de club récurrent',
	summary: 'Transformez un événement de club en série hebdomadaire, toutes les deux semaines ou mensuelle, répondez pour une seule date et annulez une occurrence sans toucher au reste.',
	sections: [
		{
			heading: 'Créer la série',
			blocks: [
				{
					type: 'p',
					text: 'Les propriétaires, admins et organisateurs d\'événements d\'un club peuvent créer des événements. Un événement récurrent est un seul événement qui se répète : tout ce que vous renseignez s\'applique donc à chaque date.',
				},
				{
					type: 'steps',
					items: [
						'Ouvrez votre club sur le web et sélectionnez **Nouvel événement**.',
						'Renseignez le **Titre**, l\'**Heure de départ** et les autres détails comme pour un événement ponctuel. L\'heure de départ choisie correspond à la première date de la série.',
						'Sous **Répétition**, choisissez **Hebdomadaire**, **Toutes les 2 semaines** ou **Mensuel** au lieu de **Unique**.',
						'Pour une série hebdomadaire ou toutes les deux semaines, choisissez les jours de la semaine sous **Ces jours-là :**. Une série mensuelle se répète le même jour du mois que la date de début.',
						'Décidez où la série s\'arrête : indiquez une date dans **Se termine le**, un nombre d\'occurrences dans **Se termine après**, ou les deux, et la première limite atteinte l\'emporte. Laissez les deux vides et la série se répète sans fin.',
						'Sélectionnez **Créer l\'événement**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Le rythme de répétition ne peut être choisi qu\'à la création de l\'événement. **Modifier l\'événement** change le titre, l\'heure, le point de rendez-vous et les autres détails pour toute la série, mais pas la fréquence de répétition.',
				},
				{
					type: 'p',
					text: 'Dans l\'app mobile, touchez **Créer un événement** dans l\'onglet **Événements** du club et choisissez **Hebdomadaire**, **Bimensuel** ou **Mensuel** sous **Récurrence**. Le téléphone répète l\'événement le jour de la semaine de sa date de début, sans date de fin ni nombre d\'occurrences : utilisez le web si la série doit s\'arrêter.',
				},
			],
		},
		{
			heading: 'Répondre pour une date',
			blocks: [
				{
					type: 'p',
					text: 'Chaque date d\'une série a ses propres réponses, sa liste de participants, sa capacité et ses résultats.',
				},
				{
					type: 'steps',
					items: [
						'Ouvrez l\'événement et utilisez **Choisir une occurrence** pour sélectionner la date. Les prochaines dates sont affichées, et **Afficher tout** déroule toutes les dates à venir sur l\'année qui suit.',
						'Choisissez **Je participe**, **Peut-être** ou **Je ne peux pas** pour cette date.',
					],
				},
				{
					type: 'p',
					text: 'Pour ajouter les dates à votre propre calendrier, sélectionnez **Ajouter au calendrier**. Pour une série, vous pouvez choisir **Ajouter cette occurrence** pour une seule date ou **Ajouter toute la série** pour toutes les dates.',
				},
			],
		},
		{
			heading: 'Annuler une occurrence',
			blocks: [
				{
					type: 'p',
					text: 'Si une date ne peut pas avoir lieu, annulez seulement cette date et laissez le reste de la série intact.',
				},
				{
					type: 'steps',
					items: [
						'Ouvrez l\'événement sur le web et choisissez la date à annuler.',
						'Sélectionnez **Annuler cette occurrence**.',
						'Ajoutez un **Motif (facultatif)**, par exemple un parcours inondé ou un jour férié, et confirmez. Sélectionnez **Conserver** si vous changez d\'avis.',
					],
				},
				{
					type: 'p',
					text: 'Toutes les personnes ayant répondu pour cette date, qu\'elles participent, aient répondu peut-être ou soient en liste d\'attente, reçoivent une notification. La date affiche **Cette occurrence a été annulée.** et plus personne ne peut y répondre. Pour la rétablir, ouvrez la date et sélectionnez **Rétablir cette occurrence**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Annuler et rétablir une date ne se fait que sur le web. **Supprimer l\'événement** supprime toutes les occurrences de la série, pas une seule.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si l\'événement est un cours payant, annuler une occurrence rembourse intégralement toutes les personnes inscrites à celle-ci. Voir [[guide:host-a-paid-yoga-class|Organiser un cours payant de yoga]].',
				},
			],
		},
	],
};
