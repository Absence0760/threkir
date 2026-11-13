import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'choose-how-your-race-starts',
	title: 'Choisir comment votre course démarre',
	summary: 'GO par l\'organisateur, GO programmé ou Fenêtre en chrono libre : quand utiliser chacun, ce que vous faites le jour J et comment les résultats sont approuvés.',
	sections: [
		{
			heading: 'Trois façons de démarrer',
			blocks: [
				{
					type: 'list',
					items: [
						'**GO par l\'organisateur** : vous armez la course et appuyez sur GO sur la ligne. Utilisez-le quand vous êtes au départ avec tout le monde, pour un départ groupé.',
						'**GO programmé** : la course démarre d\'elle-même à l\'heure que vous avez fixée. Utilisez-le quand l\'heure de départ est fixe mais que vous ne serez peut-être pas sur la ligne, ou que vous voulez courir vous-même. Vous pouvez la retarder ou l\'annuler jusque-là.',
						'**Fenêtre en chrono libre** : il n\'y a pas de départ commun. Chaque coureur chronomètre sa propre tentative entre la ligne de départ et la ligne d\'arrivée, à tout moment pendant que la fenêtre est ouverte. Utilisez-la pour un contre-la-montre hebdomadaire, ou un parcours que les gens courent quand ils le peuvent. Il n\'y a pas de temps officiel au coup de pistolet.',
					],
				},
				{
					type: 'p',
					text: 'Faites votre choix sous **Comment la course démarre** dans l\'éditeur d\'événement sur le web, pour un événement de course en groupe ou de vélo. L\'app mobile permet de gérer la course le jour J (l\'armer plus tôt, la retarder, la prolonger ou la terminer), mais le mode de départ se choisit sur le web.',
				},
			],
		},
		{
			heading: 'Régler les horaires',
			blocks: [
				{
					type: 'list',
					items: [
						'GO programmé : réglez l\'**Heure de départ** et le **Jour du départ** (le jour même, la veille ou le lendemain de l\'événement). Sous **Se termine après, jours** et **Heures**, indiquez combien de temps après le GO la course se termine d\'elle-même, sauf si vous la terminez avant.',
						'Fenêtre en chrono libre : réglez **La fenêtre ouvre à** et **Ouvre le** (de la veille de l\'événement à une semaine après), et combien de temps elle reste ouverte sous **Durée de la fenêtre, jours** et **Heures**, de 1 minute à 7 jours.',
					],
				},
				{
					type: 'p',
					text: 'Vous saisissez et voyez les horaires à l\'heure de l\'événement, dans son fuseau horaire. Sur la page de l\'événement, le panneau de course indique ce fuseau horaire et, si le vôtre est différent, votre propre heure à côté.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Les horaires sont relatifs à chaque occurrence de l\'événement. Déplacez l\'événement, ou une de ses occurrences, et ses horaires de course se déplacent avec lui. Modifiez les horaires dans l\'éditeur, et chaque occurrence qui n\'a pas encore commencé prend les nouveaux horaires.',
				},
			],
		},
		{
			heading: 'Le jour J : GO par l\'organisateur',
			blocks: [
				{
					type: 'p',
					text: 'Vous armez la course, donnez le GO et la terminez vous-même. Voir [[guide:race-day-for-hosts|Le jour de la course, côté organisateur]].',
				},
			],
		},
		{
			heading: 'Le jour J : GO programmé',
			blocks: [
				{
					type: 'list',
					items: [
						'Vous n\'avez rien à faire. La course est préparée environ un jour avant son départ et démarre d\'elle-même à l\'heure prévue.',
						'Pour vérifier les lignes du parcours plus tôt, choisissez **Armer plus tôt**.',
						'Avant le départ, le panneau de course affiche **Départ à** suivi de l\'heure et d\'un compte à rebours. Pour reculer le départ, saisissez le nombre de minutes et choisissez **Retarder le départ** ; chaque participant est prévenu que le départ a été déplacé. Choisissez **Annuler** pour annuler la course.',
						'Une fois l\'heure de départ passée, la course ne peut plus être annulée. Elle se termine d\'elle-même quand son temps est écoulé, ou choisissez **Terminer la course** pour la terminer plus tôt.',
						'Les téléphones des coureurs font le compte à rebours jusqu\'au départ selon l\'horloge du serveur et annoncent à voix haute les dernières secondes, pour que tout le monde parte ensemble.',
					],
				},
			],
		},
		{
			heading: 'Le jour J : chrono libre',
			blocks: [
				{
					type: 'list',
					items: [
						'Vous n\'avez rien à déclencher. La fenêtre s\'ouvre et se ferme d\'elle-même.',
						'Avant son ouverture, vous pouvez choisir **Retarder le départ** ou **Annuler**, comme pour une course programmée.',
						'Pendant qu\'elle est ouverte, saisissez le nombre d\'heures et choisissez **Prolonger la fenêtre** pour la garder ouverte plus longtemps (jusqu\'à 7 jours après son ouverture), ou choisissez **Fermer la fenêtre maintenant** pour la fermer plus tôt.',
						'À la fermeture de la fenêtre, un coureur qui a commencé une tentative mais n\'a envoyé aucun résultat est marqué DNF, comme lorsque vous terminez n\'importe quelle course.',
					],
				},
				{
					type: 'p',
					text: 'Chaque parcours a besoin d\'une ligne de départ et d\'une ligne d\'arrivée, et elles sont figées pour la course à l\'ouverture de la fenêtre. Voir [[guide:start-and-finish-lines|Lignes de départ et d\'arrivée]].',
				},
			],
		},
		{
			heading: 'Approuver les résultats en chrono libre',
			blocks: [
				{
					type: 'p',
					text: 'Personne ne se tient sur la ligne dans une course en chrono libre : ses résultats attendent donc votre validation par défaut, et **Approuver automatiquement les résultats soumis** est décoché au départ. Chaque résultat s\'affiche **EN ATTENTE** jusqu\'à ce que vous choisissiez **Approuver**.',
				},
				{
					type: 'p',
					text: 'Certains résultats sont retenus pour votre vérification même quand l\'approbation automatique est activée : un résultat sans franchissement de la ligne de départ (envoyé depuis une ancienne version de l\'app ou une Apple Watch), un résultat qui commence en dehors de la fenêtre, et un résultat dont les franchissements ne sont pas confirmés par les positions en direct du coureur lui-même. Un coureur qui modifie son propre temps repasse aussi en attente.',
				},
				{
					type: 'p',
					text: 'Un coureur peut faire plusieurs tentatives. Sa meilleure arrivée chronométrée par les deux lignes compte, et une tentative plus lente ne la remplace pas.',
				},
			],
		},
		{
			heading: 'Notifications de départ imminent',
			blocks: [
				{
					type: 'p',
					text: 'Environ 10 minutes avant un GO programmé, chaque participant reçoit une notification push indiquant que la course va bientôt partir, sauf si un rappel d\'événement lui est parvenu dans l\'heure précédente. Quand vous retardez un départ, ils en reçoivent une indiquant que le départ a été déplacé. Ces notifications ne sont jamais envoyées par e-mail.',
				},
				{
					type: 'p',
					text: 'Les coureurs désactivent les deux avec **Course bientôt au départ** : sur le web dans [[route:/settings/notifications|Notifications]], dans l\'app mobile sous **Notifications** dans l\'onglet **Vous**.',
				},
			],
		},
		{
			heading: 'Les coureurs ont besoin d\'une app récente',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Les courses programmées et en chrono libre nécessitent la dernière version de l\'app sur le téléphone ou la montre Wear OS. Les résultats des anciennes versions de l\'app et de l\'Apple Watch sont conservés pour votre vérification au lieu d\'être refusés.',
				},
			],
		},
	],
	sources: {
		title: '8dd0bfbefd97b39d',
		summary: '5f79511dd816ce5e',
		's0.heading': '9b26470e1beae1e9',
		's0.b0.i0': '653b79ec7d550dc5',
		's0.b0.i1': '6824deac8c3239bb',
		's0.b0.i2': '86642ad5f00798d9',
		's0.b1': '8ec9d026a8e162d9',
		's1.heading': '8ec1ca546316bf44',
		's1.b0.i0': '7f4cdf51f946ad7a',
		's1.b0.i1': 'e945e787986a825b',
		's1.b1': 'dc8ad2296857c406',
		's1.b2': 'f73aee6a8e52f86d',
		's2.heading': '3b72a06be5feeca1',
		's2.b0': 'f8eb6df29239da40',
		's3.heading': '2e53337b73ea8f70',
		's3.b0.i0': '0cd2e7973bd13122',
		's3.b0.i1': 'bb292e4077fab06b',
		's3.b0.i2': '1001bcee9a695cbd',
		's3.b0.i3': 'ad3f370a0b11c0ea',
		's3.b0.i4': '8469b5a684fd410f',
		's4.heading': '5b67193948e22e2a',
		's4.b0.i0': '689b27335b1205f7',
		's4.b0.i1': '8835ede766aaa683',
		's4.b0.i2': '92ab0d9a0804d8f9',
		's4.b0.i3': 'fe1797aedc22317e',
		's4.b1': 'fe8c69f32f52d3b4',
		's5.heading': '32e61b0e9e8b093c',
		's5.b0': 'd72ed9b7c3434bf2',
		's5.b1': '8270611445444242',
		's5.b2': '80fde57d63447dcd',
		's6.heading': 'b0f6668439cdc509',
		's6.b0': '7f18ce5f91bea911',
		's6.b1': '75dcfe5f36ba4e0a',
		's7.heading': '81f746d1e62c98a8',
		's7.b0': '00727d27f2897451',
	},
};
