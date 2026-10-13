import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'recurring-events',
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
						'Ouvrez l\'événement et utilisez **Choisir une occurrence** pour sélectionner la date. Les prochaines dates sont affichées, et **Afficher les 12 à venir** (le nombre indique combien de dates restent) déroule toutes les dates à venir sur l\'année qui suit.',
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
	sources: {
		title: 'e613c3be8d106d58',
		summary: '16e60fe00d2cd802',
		's0.heading': '718e1069f51a2cb4',
		's0.b0': '3db51494677d6358',
		's0.b1.i0': '7b361a4f9398e384',
		's0.b1.i1': '17734b394312df43',
		's0.b1.i2': '0f73dbb856a7fa67',
		's0.b1.i3': 'a002823ae62a3df3',
		's0.b1.i4': 'e54a7bd9afd1d160',
		's0.b1.i5': 'ec48c553acdf742f',
		's0.b2': 'df7167c739a9ea9e',
		's0.b3': 'c40bdc990b5425db',
		's1.heading': 'd0f06618475ee3d1',
		's1.b0': 'fb3d5e80f695a45d',
		's1.b1.i0': 'af04da638393359f',
		's1.b1.i1': 'e208d82edea8262f',
		's1.b2': 'c2477719db027ba7',
		's2.heading': 'f95356ca142cc32c',
		's2.b0': '2836a3e020560d5f',
		's2.b1.i0': 'db8f532e330056ff',
		's2.b1.i1': '0c4ddfc33914c615',
		's2.b1.i2': 'fa7eaa32d4fdc37a',
		's2.b2': 'b34bc386e0fc3cb4',
		's2.b3': 'c1fb4f63833b6418',
		's2.b4': 'dfb7d75cf658eb0a',
	},
};
