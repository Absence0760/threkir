import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'what-pro-includes',
	title: 'Ce que comprend Pro',
	summary: 'Tous les écrans de Threkir sont gratuits ; Pro augmente votre quota de Coach IA et fait passer certains traitements en arrière-plan en tête de file.',
	sections: [
		{
			heading: 'Ce qui reste gratuit',
			blocks: [
				{
					type: 'p',
					text: 'Rien dans l\'app n\'est réservé à Pro. Les comptes gratuits bénéficient de l\'enregistrement illimité sur téléphone et montre, des itinéraires, des plans d\'entraînement et des chiffres qui les sous-tendent, des clubs et événements, du fil social, des contacts de sécurité, des imports et des sauvegardes.',
				},
			],
		},
		{
			heading: 'Ce que Pro ajoute',
			blocks: [
				{
					type: 'list',
					items: [
						'**Coach IA — 10/jour** : dix messages au Coach par jour au lieu de deux. Le compteur est remis à zéro à minuit UTC.',
						'Des réponses du Coach plus longues et plus approfondies, qui peuvent prendre en compte davantage de vos courses.',
						'**Map-matching prioritaire** : vos traces GPS sont calées sur les routes avant celles des comptes gratuits, elles sont donc prêtes plus tôt.',
						'**Exports cloud prioritaires** : jusqu\'à 8 exports groupés GPX par heure au lieu de 2.',
						'**Génération de parcours côté serveur** : des boucles tracées sur le vrai réseau de rues quand vous générez un itinéraire par distance. Les comptes gratuits ont toujours la génération de boucles, calculée dans le navigateur.',
						'Des descriptions d\'itinéraire plus riches : sur la page d\'un itinéraire, **Améliorer avec l\'IA** transforme la description standard en un paragraphe plus complet.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Certaines de ces fonctionnalités dépendent de services qui ne sont peut-être pas encore activés. La carte Pro dans [[route:/settings/upgrade|Pro et soutien]] ne liste que ce qui fonctionne aujourd\'hui ; si elle indique **Pro débloque le coach IA — bientôt disponible.**, Pro ne peut pas encore être acheté.',
				},
			],
		},
		{
			heading: 'Comment obtenir Pro',
			blocks: [
				{
					type: 'p',
					text: 'Pro est un abonnement mensuel ou annuel ; la carte Pro affiche les prix en vigueur. L\'endroit où vous pouvez l\'acheter dépend de votre appareil :',
				},
				{
					type: 'list',
					items: [
						'Sur un iPhone, ouvrez **Pro et soutien** dans l\'onglet **Vous** et abonnez-vous via l\'App Store.',
						'Sur le web, ouvrez [[route:/settings/upgrade|Pro et soutien]] dans les Paramètres. S\'il est indiqué **L\'abonnement sur le web arrive bientôt.**, abonnez-vous plutôt dans l\'app iPhone.',
					],
				},
				{
					type: 'p',
					text: 'Pro est lié à votre compte, pas à votre appareil : un abonnement acheté sur un appareil fonctionne partout où vous vous connectez.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Les prix sont en dollars américains, et l\'App Store facture le prix fixé pour votre pays. Certains pays et moyens de paiement ne peuvent pas être pris en charge par notre prestataire de paiement.',
				},
			],
		},
		{
			heading: 'Gérer ou résilier',
			blocks: [
				{
					type: 'list',
					items: [
						'Résiliez ou modifiez votre formule là où vous l\'avez souscrite : l\'App Store, le Play Store ou le portail de facturation web. **Gérer l\'abonnement** vous y mène.',
						'Sur un nouveau téléphone, touchez **Restaurer les achats** dans **Pro et soutien** pour récupérer un abonnement existant.',
						'Vous préférez une contribution ponctuelle ? **Faire un don** se trouve sur la même page.',
					],
				},
			],
		},
	],
	sources: {
		title: '4267811678bae9e8',
		summary: '959c30d7818df50f',
		's0.heading': '1319c99f2d10de2f',
		's0.b0': '4512e0ee677c9a74',
		's1.heading': '28933395a25968d0',
		's1.b0.i0': '719256df99c524da',
		's1.b0.i1': '2cc8c412ba418164',
		's1.b0.i2': '3be7590bced0492d',
		's1.b0.i3': 'a120796543f347bd',
		's1.b0.i4': 'abbb1f922ffbfa10',
		's1.b0.i5': 'dd0fa90eed200d7c',
		's1.b1': '076479f3bd42d0b5',
		's2.heading': '912eb19f965419db',
		's2.b0': 'ee79a267ee574aa9',
		's2.b1.i0': 'd455f1337a2fbaed',
		's2.b1.i1': 'f74f301604c6ba73',
		's2.b2': 'fd72c472718d9474',
		's2.b3': '0e5dc12fffad6bf9',
		's3.heading': '797ca5cca61c8cd4',
		's3.b0.i0': 'bb4062dcb71c0913',
		's3.b0.i1': '736765a7a1193432',
		's3.b0.i2': '1d83469669e327f0',
	},
};
