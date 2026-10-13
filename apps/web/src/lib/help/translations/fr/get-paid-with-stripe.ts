import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'get-paid-with-stripe',
	title: 'Être payé pour les événements que vous organisez',
	summary: 'Connectez une seule fois un compte de paiement Stripe pour que vos cours et événements puissent être payants, l\'argent vous revenant à vous plutôt qu\'au club.',
	sections: [
		{
			heading: 'Avant de commencer',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'L\'inscription payante n\'est pas encore active. Faire payer un événement exige deux choses : votre propre compte Stripe connecté ici, et l\'activation des paiements par la plateforme. Tant que ces deux conditions ne sont pas réunies, personne ne peut être débité. Si appuyer sur **Configurer les paiements** affiche **Les paiements ne sont pas encore configurés sur cette version.**, c\'est la seconde qui manque encore et vous n\'avez rien à faire pour l\'instant.',
				},
				{
					type: 'p',
					text: 'Les versements vous appartiennent à *vous*, pas à un club. L\'argent d\'un événement va à la personne qui l\'organise : un co-organisateur qui n\'anime jamais de cours ne voit jamais d\'argent qui n\'est pas le sien, et vous gardez vos revenus si vous cessez d\'organiser pour un club. Un seul compte de paiement couvre tous les clubs pour lesquels vous organisez et tous les types d\'événements, [[guide:set-up-a-race|une course]] comprise.',
				},
			],
		},
		{
			heading: 'Connecter votre compte de paiement',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez [[route:/settings/payouts|Paramètres, Paiements]] sur le web.',
						'Appuyez sur **Configurer les paiements**. Vous êtes redirigé vers Stripe pour saisir vos informations et le compte bancaire sur lequel vous voulez être payé.',
						'Terminez les étapes de Stripe. À votre retour, la page affiche votre statut.',
						'S\'il indique **Configuration incomplète — terminez pour commencer à facturer** ou **Votre compte de paiement nécessite une action avant de pouvoir encaisser**, appuyez sur **Terminer la configuration des paiements** pour retourner sur Stripe et reprendre là où vous en étiez.',
					],
				},
			],
		},
		{
			heading: 'Ce que signifie le statut',
			blocks: [
				{
					type: 'list',
					items: [
						'**Prêt à encaisser** : Stripe a activé les paiements sur votre compte, et **Ouvrir le tableau de bord Stripe** vous mène à votre compte Stripe. C\'est ce que signifie « paiements activés », et c\'est le seul état dans lequel l\'interrupteur **Faire payer cet événement** d\'un nouvel événement peut être activé.',
						'**Configuration incomplète — terminez pour commencer à facturer** : Stripe attend encore quelque chose de votre part avant d\'accepter un paiement.',
						'**Votre compte de paiement nécessite une action avant de pouvoir encaisser** : Stripe a restreint le compte, généralement parce qu\'il demande plus d\'informations. **Terminer la configuration des paiements** vous mène à ce qui est demandé.',
					],
				},
				{
					type: 'p',
					text: 'Tant que vous n\'êtes pas prêt à encaisser, le formulaire d\'événement affiche **Configurez les paiements pour faire payer les événements.** avec un lien **Configurer les paiements** qui ramène à cette page.',
				},
			],
		},
		{
			heading: 'Frais et répartition des rôles',
			blocks: [
				{
					type: 'p',
					text: 'La plateforme prélève une petite commission sur chaque inscription, affichée comme **Frais de plateforme** dans vos revenus. La plateforme est le marchand officiel : le paiement porte son nom sur le relevé de l\'acheteur, les remboursements sont effectués par la plateforme selon la politique de remboursement que vous fixez pour chaque événement, et un paiement contesté est prélevé sur le compte Stripe de la plateforme, pas sur le vôtre. Quand une commande est entièrement remboursée, les frais de plateforme correspondants sont eux aussi restitués.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ne remboursez pas un acheteur à la main dans Stripe. Utilisez les parcours prévus par l\'app ([[guide:refund-policies|l\'annulation par l\'acheteur]] ou [[guide:cancel-a-class|l\'annulation d\'une occurrence]]), qui annulent ensemble votre versement et les frais de plateforme et gardent vos chiffres de revenus justes.',
				},
			],
		},
		{
			heading: 'Voir ce que vous avez gagné',
			blocks: [
				{
					type: 'p',
					text: 'La section **Revenus** de la même page montre ce qui vous a été versé pour vos cours, un bloc par mois et par devise. Un cours est classé dans le mois où il a eu lieu, dans son propre fuseau horaire, et non dans le mois du paiement : « mes cours d\'octobre » désigne donc les cours qui ont eu lieu en octobre.',
				},
				{
					type: 'list',
					items: [
						'**Inscriptions**, **Brut**, **Remboursé** et **Frais de plateforme** pour le mois, puis **Net pour vous** à la fin.',
						'Un détail par cours avec les colonnes **Cours** et **Date**.',
						'Un remboursement renvoyé par la banque est exclu des totaux jusqu\'à sa résolution, et la section indique combien il y en a.',
					],
				},
				{
					type: 'p',
					text: 'Avant que quiconque ait payé, elle affiche **Aucune inscription payée pour l’instant. Dès que quelqu’un paie l’un de vos cours, il apparaît ici.** Les revenus ne sont visibles que sur le web pour le moment.',
				},
			],
		},
	],
	sources: {
		title: 'f9207157d1280332',
		summary: '790080559509072a',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '94bdd45ffa45992b',
		's0.b1': 'a2c35333af5a1b69',
		's1.heading': '3f872765a64cbf87',
		's1.b0.i0': 'e50bbd6128265cce',
		's1.b0.i1': '0f46885c40eac7c9',
		's1.b0.i2': '5c865b5f5c133459',
		's1.b0.i3': '8dda9f151d4fc524',
		's2.heading': '1efee8cc7e563d7a',
		's2.b0.i0': '02332a68186a1ac7',
		's2.b0.i1': '7215a841b76d02d7',
		's2.b0.i2': '482a0774b06a0a05',
		's2.b1': '97218ad8cd1cbafc',
		's3.heading': 'dd310d8f72e99c50',
		's3.b0': '67194d07a6c76aca',
		's3.b1': 'b0ca08b2dbcff463',
		's4.heading': 'e819e6fcb745f74c',
		's4.b0': '158c0402a17ba033',
		's4.b1.i0': '1f9a53c012335688',
		's4.b1.i1': '69d92aabe5b8e3c6',
		's4.b1.i2': 'da7f4f45de54e110',
		's4.b2': 'e6e13ff04eb65dc4',
	},
};
