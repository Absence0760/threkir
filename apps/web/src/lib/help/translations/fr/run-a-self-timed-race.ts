import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'run-a-self-timed-race',
	title: 'Courir une course en chrono libre',
	summary: 'Inscrivez-vous à une épreuve ouverte pendant une fenêtre de temps, marquez votre course comme votre tentative et courez de la ligne de départ à la ligne d\'arrivée quand cela vous convient.',
	sections: [
		{
			heading: 'Qu\'est-ce qu\'une course en chrono libre',
			blocks: [
				{
					type: 'p',
					text: 'Une course en chrono libre n\'a pas de départ groupé. L\'organisateur ouvre une fenêtre, qui peut durer jusqu\'à une semaine, et vous courez le parcours quand vous voulez tant qu\'elle est ouverte. Votre temps court du moment où vous franchissez la ligne de départ jusqu\'à celui où vous franchissez la ligne d\'arrivée : il n\'y a donc pas de temps officiel au coup de pistolet.',
				},
				{
					type: 'p',
					text: 'Vous enregistrez votre tentative avec l\'app mobile ou une montre Wear OS. Le web sert à vous inscrire et à consulter les résultats ; un navigateur ne peut pas enregistrer une course.',
				},
			],
		},
		{
			heading: 'Avant de partir',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez l\'événement de la course, sur le web ou dans l\'app mobile.',
						'S\'il y a plusieurs parcours, choisissez d\'abord le vôtre.',
						'Choisissez **Participer et tenter**. Si vous avez déjà répondu **Je participe**, vous êtes déjà inscrit.',
						'Ouvrez l\'app une fois pendant que vous avez du réseau, avant de partir. Elle connaît alors la course : le bandeau de course et votre tentative fonctionnent même là où il n\'y a pas de réseau.',
					],
				},
			],
		},
		{
			heading: 'Lancer votre tentative',
			blocks: [
				{
					type: 'steps',
					items: [
						'Dans l\'onglet Courir de l\'app mobile, le bandeau de course affiche **Chrono libre** et l\'heure de fermeture de la fenêtre.',
						'Touchez **Cette course est ma tentative**. Le bouton devient **Tentative prête : touchez Démarrer** ; touchez-le de nouveau si vous changez d\'avis.',
						'Appuyez sur Démarrer avant d\'atteindre la ligne de départ, puis franchissez la ligne de départ dans le sens du parcours.',
					],
				},
				{
					type: 'p',
					text: 'Sur une montre Wear OS, l\'écran avant le départ affiche CHRONO LIBRE. Touchez **Cette course est ma tentative**, puis Démarrer.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Une course que vous ne marquez pas comme votre tentative ne rejoint jamais l\'épreuve : elle n\'envoie aucune position en direct et n\'obtient aucun résultat. Ainsi, une course que vous ne vouliez pas courir en compétition n\'apparaît jamais au classement.',
				},
			],
		},
		{
			heading: 'Tentatives et résultat',
			blocks: [
				{
					type: 'list',
					items: [
						'Vous pouvez faire plusieurs tentatives tant que la fenêtre est ouverte. Touchez **Cette course est ma tentative** avant chacune.',
						'Votre meilleure arrivée chronométrée par les deux lignes compte. Une tentative plus lente ne la remplace pas.',
						'Votre résultat peut attendre la validation de l\'organisateur. D\'ici là, il s\'affiche en attente et n\'a pas de place.',
						'Un résultat sans franchissement de la ligne de départ, par exemple envoyé depuis une Apple Watch ou une ancienne version de l\'app, est conservé, mais l\'organisateur le vérifie avant qu\'il compte.',
					],
				},
				{
					type: 'p',
					text: 'La signification des temps au classement est expliquée dans [[guide:race-results-explained|Comprendre les résultats de course]].',
				},
			],
		},
		{
			heading: 'Si votre téléphone a manqué une ligne',
			blocks: [
				{
					type: 'p',
					text: 'Votre téléphone ou votre montre annonce « Ligne de départ franchie, chrono lancé » quand il vous voit franchir la ligne de départ, et enregistre votre arrivée à la ligne d\'arrivée. S\'il en manque une, par exemple sous les arbres ou quand vous partez un peu à côté de la ligne :',
				},
				{
					type: 'list',
					items: [
						'À l\'arrivée, touchez Arrêter, puis **Terminer la course**. Une fois que vous avez couvert 90 % du parcours, cela envoie votre temps, et l\'organisateur l\'examine avant qu\'il compte.',
						'Ou rechronométrez ensuite votre tentative à partir de sa trace : ouvrez la course sur le web et choisissez **Rechronométrer depuis ma trace**. La trace est chronométrée par les lignes de l\'épreuve, et le résultat remplace un résultat en attente d\'examen, ou un résultat plus lent. Vous pouvez le faire jusqu\'à 24 heures après la fermeture de la fenêtre.',
						'Vous avez couru avec une Apple Watch ? Elle ne détecte pas les lignes : rechronométrer à partir de votre trace est donc le moyen d\'obtenir pour votre tentative un résultat chronométré par les lignes.',
					],
				},
				{
					type: 'p',
					text: 'Pour en savoir plus sur le rechronométrage, voir [[guide:race-results-explained|Comprendre les résultats de course]].',
				},
			],
		},
	],
	sources: {
		'title': '980e3fe539fa87ed',
		'summary': '8200cb3990ca1c84',
		's0.heading': 'da16fddd6466ff82',
		's0.b0': 'b166c8e10ca64251',
		's0.b1': '9eb15ab29b32b50a',
		's1.heading': 'c682ac1a8b55d5bd',
		's1.b0.i0': 'f2699d62a364214c',
		's1.b0.i1': '15f502c0495a6810',
		's1.b0.i2': 'd67ce3877679d3b7',
		's1.b0.i3': 'd5058d744cf24c6b',
		's2.heading': '6e3e520b08e75a87',
		's2.b0.i0': '6b5b44bd7545a139',
		's2.b0.i1': '48bf3f903a530a73',
		's2.b0.i2': 'ff90c543a96100a6',
		's2.b1': '34ded6bec1fb4447',
		's2.b2': 'e9496d6a3325b124',
		's3.heading': '4ad1d4e8c17417b8',
		's3.b0.i0': 'a0858a05aad2d12a',
		's3.b0.i1': '82cda99fabf47908',
		's3.b0.i2': 'a6113125dae261a1',
		's3.b0.i3': '8e98409f10047bd7',
		's3.b1': '71fadd9d562da318',
		's4.heading': '9f401b8bc89ad9f0',
		's4.b0': 'c83ffd00a5d79eaf',
		's4.b1.i0': '371c0ea180b0a2cc',
		's4.b1.i1': 'd4b32e20b9afba25',
		's4.b1.i2': '30e86640bcd591b4',
		's4.b2': '172cd34b60d4d532',
	},
};
