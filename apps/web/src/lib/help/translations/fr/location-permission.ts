import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'location-permission',
	title: 'Accès à la localisation pour enregistrer vos courses',
	summary: 'Quelle option de localisation choisir sur Android et sur iPhone, ce que chacune change pour vos courses et comment la modifier plus tard dans les réglages.',
	sections: [
		{
			heading: 'Pourquoi l\'app demande votre position',
			blocks: [
				{
					type: 'p',
					text: 'Votre position trace la carte d\'une course et mesure sa distance et son allure. Sans elle, une course enregistre toujours le temps et les pas, mais ni carte, ni distance, ni allure.',
				},
				{
					type: 'p',
					text: 'La demande arrive pendant la configuration : après la page **Accès à la localisation**, toucher **Accorder l\'autorisation** ouvre la demande de votre téléphone. Si vous refusez, l\'app vous le signale et propose **Ouvrir les réglages**. Si vous n\'avez toujours pas autorisé l\'accès quand vous touchez **DÉMARRER**, votre téléphone peut vous le redemander.',
				},
			],
		},
		{
			heading: 'Sur Android',
			blocks: [
				{
					type: 'p',
					text: 'La première demande d\'Android ne peut accorder l\'accès que pendant l\'utilisation de l\'app. Pour que la course reste suivie écran éteint, il faut **Toujours autoriser**, qu\'Android ne permet de choisir que dans les paramètres.',
				},
				{
					type: 'steps',
					items: [
						'Dans la demande, laissez **Précise** sélectionné et touchez **Lorsque vous utilisez l\'appli**.',
						'Avant votre première course, l\'app affiche **Autoriser la localisation en permanence**. Touchez **Ouvrir les réglages**.',
						'Sous **Autorisations**, touchez **Position**, choisissez **Toujours autoriser**, puis revenez dans l\'app.',
					],
				},
				{
					type: 'p',
					text: 'Si vous touchez **Démarrer quand même**, la course s\'enregistre normalement tant que l\'app est à l\'écran. Écran éteint ou dans une autre app, Android peut cesser d\'envoyer votre position : le chrono continue et rien de ce qui est déjà enregistré n\'est perdu, mais la distance parcourue pendant ce temps n\'est pas comptée. Dans ce cas, un message commençant par **Le suivi a été mis en pause pendant votre absence** s\'affiche à votre retour, avec un bouton **Réglages**.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Le rappel avant une course ne s\'affiche qu\'une fois. Il revient seulement si vous aviez autorisé l\'accès en permanence et que cet accès a été retiré ensuite, par exemple quand Android réinitialise les autorisations des apps que vous n\'avez pas ouvertes depuis longtemps.',
				},
				{
					type: 'list',
					items: [
						'Avec **Approximative**, la position est trop imprécise pour mesurer une course : vous verrez **GPS faible — distance en pause** pendant toute la course.',
						'**Uniquement cette fois-ci** vaut pour la course que vous allez lancer, et la question vous sera reposée la prochaine fois.',
						'Avec **Ne pas autoriser**, les courses n\'enregistrent que le temps et les pas.',
					],
				},
			],
		},
		{
			heading: 'Sur iPhone',
			blocks: [
				{
					type: 'p',
					text: 'Sur iPhone, l\'accès pendant l\'utilisation de l\'app suffit : une course continue de s\'enregistrer écran verrouillé ou pendant que vous utilisez une autre app. L\'app ne demande jamais **Toujours**, et vous n\'en avez pas besoin.',
				},
				{
					type: 'steps',
					items: [
						'Dans la demande, touchez **Autoriser lorsque l\'app est active**.',
						'Laissez la position exacte activée dans la demande. Sans elle, votre position est trop imprécise pour mesurer la distance, et la course affiche **GPS faible — distance en pause**.',
					],
				},
				{
					type: 'p',
					text: '**Autoriser une fois** ne vaut que pour cette course, et la question vous sera reposée la prochaine fois. Avec **Ne pas autoriser**, les courses n\'enregistrent que le temps et les pas.',
				},
			],
		},
		{
			heading: 'Économiseurs de batterie',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Certains téléphones Android (Samsung, Xiaomi, OnePlus et d\'autres) mettent les apps en veille pour économiser la batterie, ce qui peut interrompre l\'enregistrement d\'une longue course écran éteint, même avec **Toujours autoriser**. Avant votre première course, l\'app affiche une fois **Maintenir l\'enregistrement actif en arrière-plan** : touchez **Ouvrir les réglages** et excluez Threkir de l\'optimisation de la batterie. Si vous avez touché **Pas maintenant**, ouvrez la page de l\'app dans les paramètres de votre téléphone, touchez **Batterie** et choisissez **Sans restriction**. Les noms varient un peu d\'un fabricant à l\'autre.',
				},
			],
		},
		{
			heading: 'Modifier plus tard',
			blocks: [
				{
					type: 'p',
					text: 'Sur Android :',
				},
				{
					type: 'steps',
					items: [
						'Ouvrez les **Paramètres** de votre téléphone et touchez **Applications**, puis **Threkir**.',
						'Touchez **Autorisations**, puis **Position**.',
						'Choisissez **Toujours autoriser** et activez **Utiliser la position exacte**.',
					],
				},
				{
					type: 'p',
					text: 'Sur iPhone :',
				},
				{
					type: 'steps',
					items: [
						'Ouvrez **Réglages** › **Confidentialité et sécurité** › **Service de localisation**, et vérifiez que **Service de localisation** est activé.',
						'Touchez **Threkir** et choisissez **Lorsque l\'app est active**.',
						'Activez **Position exacte**.',
					],
				},
				{
					type: 'p',
					text: 'Si la localisation est désactivée ou bloquée quand vous lancez une course, l\'écran de course vous le signale et son bouton **Réglages** vous mène au bon endroit.',
				},
			],
		},
		{
			heading: 'Ce que l\'app fait de votre position',
			blocks: [
				{
					type: 'list',
					items: [
						'Elle lit votre position pendant que vous enregistrez une course, et quand une carte se centre sur vous, par exemple quand vous créez un itinéraire ou placez une zone de confidentialité. Elle ne vous suit pas entre les courses.',
						'Sur Android, une notification s\'affiche pendant l\'enregistrement d\'une course, si vous autorisez les notifications.',
						'Le tracé d\'une course reste sur votre téléphone jusqu\'à sa synchronisation avec votre compte ou jusqu\'à ce que vous le partagiez, et qui peut le voir dépend de vos réglages de confidentialité : voir [[guide:your-data-and-privacy|vos données et votre vie privée]].',
						'Pour masquer votre domicile, configurez des [[guide:privacy-zones|zones de confidentialité]]. Votre position en direct n\'est partagée que si vous activez le [[guide:live-tracking-and-safety|suivi en direct]].',
					],
				},
			],
		},
	],
	sources: {
		'title': '583816a170012c19',
		'summary': '56769a6e224ff156',
		's0.heading': '794b04c19c7668d8',
		's0.b0': 'af2524b060ff7e41',
		's0.b1': 'c4efda4e34e087e7',
		's1.heading': 'd085d4c0606e9a65',
		's1.b0': 'f87947ee024ca95d',
		's1.b1.i0': '74eca884f8eb053b',
		's1.b1.i1': 'bc08250477141230',
		's1.b1.i2': 'cd926bc8428f270d',
		's1.b2': '3f9237c89f00534f',
		's1.b3': '6c15e5f41c0dbad5',
		's1.b4.i0': '96fb29287371ef73',
		's1.b4.i1': 'd35c46ecb6f1579e',
		's1.b4.i2': '09d7ce333fe83b8c',
		's2.heading': '873081b6807b4197',
		's2.b0': '6912b4c52f4c4037',
		's2.b1.i0': '302121c948975146',
		's2.b1.i1': '7bcc2b01bf8a35ab',
		's2.b2': 'dd5515e417bcce18',
		's3.heading': 'd91eca07ad12c491',
		's3.b0': '5ecc6e3ad1cacf65',
		's4.heading': '8489bd921c93cd06',
		's4.b0': '8a324e6ccca0ee87',
		's4.b1.i0': '682f9bd3caa2bb73',
		's4.b1.i1': '8cad8da0c6d30e3e',
		's4.b1.i2': '007cea366706e1e4',
		's4.b2': '1eb507e8f5d10b2b',
		's4.b3.i0': '29ad09bb32235340',
		's4.b3.i1': '54f8b50ec24d5250',
		's4.b3.i2': '4bbab96422f563b9',
		's4.b4': '20e869463ad7c51c',
		's5.heading': '11a805eb39c14582',
		's5.b0.i0': 'e4acbdfc462c84a6',
		's5.b0.i1': '1a49253f9adf5652',
		's5.b0.i2': '79d0adcf35c722c0',
		's5.b0.i3': 'f79c6d8e7f96a30f',
	},
};
