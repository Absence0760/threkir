import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'racing-in-a-race',
	title: 'Participer à une course en direct',
	summary: 'Inscrivez-vous, choisissez votre parcours, démarrez l\'enregistrement sur la ligne ou après le GO et laissez votre téléphone ou votre montre vous chronométrer à l\'arrivée.',
	sections: [
		{
			heading: 'Quels appareils peuvent participer',
			blocks: [
				{
					type: 'list',
					items: [
						'App Android : prise en charge complète. Elle affiche le bandeau de course, envoie votre position en direct et enregistre votre arrivée automatiquement.',
						'App iPhone : elle exécute le même code qu\'Android, mais n\'a pas encore été testée sur iPhone lors d\'une vraie course.',
						'Montre Wear OS : prise en charge complète au poignet, y compris l\'arrivée automatique. L\'inscription et le choix du parcours se font toujours sur le web ou le téléphone.',
						'Apple Watch : prise en charge préliminaire seulement. Elle affiche le bandeau de course, envoie votre position et transmet votre temps via votre iPhone, mais elle n\'a pas d\'arrivée automatique et n\'a pas fait ses preuves lors d\'une vraie course. Gardez votre téléphone sur vous en secours.',
						'Web : servez-vous-en pour vous inscrire, choisir un parcours et consulter les résultats. Un navigateur ne peut pas enregistrer de course.',
					],
				},
			],
		},
		{
			heading: 'S\'inscrire et choisir un parcours',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez l\'événement de la course.',
						'S\'il y a plusieurs parcours, choisissez le vôtre dans **Ton parcours** sur le web. Dans l\'app mobile, on vous demande **Choisissez votre parcours** quand vous touchez **Je viens**.',
						'Touchez **Je participe**. Seule une inscription **Je participe** reçoit les alertes de course sur votre appareil ; **Peut-être** ne les reçoit pas.',
					],
				},
				{
					type: 'p',
					text: 'Vous avez changé d\'avis ? Sur le web, choisissez un autre parcours dans **Ton parcours** (vous verrez « Parcours mis à jour. »). Dans l\'app mobile, touchez **Changer de parcours**. Fixez votre parcours avant de lancer l\'enregistrement : votre téléphone ou votre montre le lit au début de l\'enregistrement de la course, et votre résultat va au classement de ce parcours.',
				},
			],
		},
		{
			heading: 'Course armée et course en direct',
			blocks: [
				{
					type: 'p',
					text: 'Quand l\'organisateur arme la course, l\'onglet Courir de l\'app mobile affiche **Course armée** avec « en attente du départ ». La montre Wear OS affiche « COURSE PRÊTE » au-dessus de son bouton Démarrer. Quand l\'organisateur donne le GO, cela devient **Course EN DIRECT** (« COURSE EN DIRECT » sur la montre) avec le temps écoulé et « touchez Démarrer ».',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Votre téléphone ou votre montre ne démarre pas l\'enregistrement tout seul : appuyez vous-même sur Démarrer. Vous pouvez démarrer sur la ligne pendant que la course affiche **Course armée**, ou dès que vous voyez **Course EN DIRECT**. Un enregistrement lancé en avance est rattaché à la course au GO, sur le téléphone comme sur une montre Wear OS, et votre temps puce compte alors à partir du GO plutôt qu\'à partir du moment où vous avez appuyé sur Démarrer.',
				},
				{
					type: 'p',
					text: 'L\'app mobile recherche les courses auxquelles vous avez répondu **Je viens** et qui commencent dans la journée qui suit. Si le bandeau tarde à apparaître, gardez l\'app ouverte sur l\'onglet Courir pendant une minute.',
				},
			],
		},
		{
			heading: 'Arrivée automatique',
			blocks: [
				{
					type: 'p',
					text: 'Vous n\'avez rien à appuyer à l\'arrivée. Votre téléphone ou votre montre Wear OS enregistre votre arrivée quand ces deux conditions sont réunies :',
				},
				{
					type: 'list',
					items: [
						'vous êtes à moins de 30 m de la ligne d\'arrivée, et',
						'vous avez couvert au moins 90 % de la distance de votre parcours.',
					],
				},
				{
					type: 'p',
					text: 'Votre temps est pris au moment où vous étiez le plus proche de l\'arrivée, et non au premier moment où vous êtes passé à moins de 30 m. La règle des 90 % évite qu\'un parcours en boucle, qui part de l\'endroit où il arrive, enregistre votre arrivée dès la première seconde. Le téléphone affiche « Arrivée ! » avec votre temps officiel, et votre enregistrement s\'arrête.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si votre parcours n\'a pas d\'itinéraire ou pas de distance, il n\'y a pas d\'arrivée automatique. Utilisez Arrêter, puis **Terminer la course** quand vous franchissez la ligne.',
				},
			],
		},
		{
			heading: 'S\'arrêter pendant la course',
			blocks: [
				{
					type: 'p',
					text: 'Pendant une course en direct, Arrêter ne met pas fin à votre course. Cela met votre enregistrement en pause et affiche **Course en pause**. Le chrono de la course continue de tourner.',
				},
				{
					type: 'list',
					items: [
						'**Reprendre la course** relance l\'enregistrement.',
						'**Terminer la course** met fin à votre course maintenant. Si vous avez couvert au moins 90 % du parcours, c\'est une arrivée manuelle à cet instant.',
						'En dessous de 90 %, le bouton indique **Terminer en abandon (DNF)**, et terminer enregistre un DNF.',
					],
				},
				{
					type: 'p',
					text: 'Sur une montre Wear OS, l\'écran de pause propose « Go » pour reprendre, et vous maintenez **Fin** appuyé pour terminer.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Terminer avant 90 % du parcours enregistre un DNF. Si vous vous êtes seulement arrêté pour refaire un lacet, choisissez **Reprendre la course**.',
				},
			],
		},
		{
			heading: 'Pas de réseau à l\'arrivée',
			blocks: [
				{
					type: 'p',
					text: 'Le réseau est souvent mauvais sur les lignes d\'arrivée. Votre téléphone et votre montre Wear OS enregistrent d\'abord votre résultat et l\'envoient dès qu\'ils se reconnectent : il n\'est donc pas perdu. Il doit nous parvenir dans les 24 heures qui suivent la fin de la course par l\'organisateur. Ne vous déconnectez pas de l\'app avant qu\'il ait été envoyé.',
				},
			],
		},
		{
			heading: 'Temps officiel, temps puce et départs tardifs',
			blocks: [
				{
					type: 'list',
					items: [
						'Le **Temps officiel** court du moment où l\'organisateur a donné le GO jusqu\'à votre arrivée. C\'est sur ce temps que vous êtes classé.',
						'Le **Temps puce** court du moment où vous avez appuyé sur Démarrer jusqu\'à votre arrivée, pauses comprises. Si vous avez appuyé sur Démarrer avant le GO, il court à partir du GO : il n\'est donc jamais plus long que votre temps officiel.',
						'Si vous partez plus de 5 minutes après le GO, ou si votre première position est à plus de 200 m du départ du parcours, l\'app mobile affiche un avis de départ tardif et une montre Wear OS garde **Départ tardif** sous le chrono de course. Votre temps officiel compte toujours à partir du GO : un départ tardif le rend donc plus long que votre temps puce.',
					],
				},
				{
					type: 'p',
					text: 'Pour en savoir plus sur la lecture du classement, voir [[guide:race-results-explained|Comprendre les résultats de course]].',
				},
			],
		},
		{
			heading: 'Si l\'organisateur termine la course avant vous',
			blocks: [
				{
					type: 'p',
					text: 'Si l\'organisateur termine la course avant votre arrivée, votre téléphone vous en informe et votre montre affiche « Course terminée ». Votre course continue d\'être enregistrée comme une course normale, mais votre appareil n\'envoie aucun résultat de course. Si vous aviez déjà envoyé une position en direct, la course vous marque DNF.',
				},
			],
		},
	],
	sources: {
		title: '3ce73ee9613bf595',
		summary: '68756b47ced58dbe',
		's0.heading': 'ac0fdba8f9fafc40',
		's0.b0.i0': 'a9ea22844fb2d329',
		's0.b0.i1': 'c4096345432d33e6',
		's0.b0.i2': 'eb58207e7be0195c',
		's0.b0.i3': '1bcd7ec3984d3f4b',
		's0.b0.i4': 'ef48ea3447ed4a81',
		's1.heading': 'f00c55d7857a6dce',
		's1.b0.i0': '30eeadd878d7b098',
		's1.b0.i1': '525a552fd753b987',
		's1.b0.i2': '9efc1bb52d90e6ef',
		's1.b1': '55c32b3a7d7a241c',
		's2.heading': 'ed31d49e898938c8',
		's2.b0': 'f4ff1ecc36a2cf8e',
		's2.b1': '75851b29576f9617',
		's2.b2': 'ddeff25fbc81b659',
		's3.heading': 'b1c0468dde456524',
		's3.b0': '3b0504a88d8b1324',
		's3.b1.i0': 'd77e68893353ede5',
		's3.b1.i1': '56f20f41366f1cfa',
		's3.b2': 'e2edf18b6d5204ad',
		's3.b3': 'f25312164622198b',
		's4.heading': '5df934589d491767',
		's4.b0': 'f1a6d8c09124a7d8',
		's4.b1.i0': '7a35b26309af9c5b',
		's4.b1.i1': 'f2cbc2dc9b04ff5b',
		's4.b1.i2': '630eba7ef0538b75',
		's4.b2': 'a0e378aecf393dda',
		's4.b3': 'b99b4c432279d3ea',
		's5.heading': '19cee1ff0ce4a9e3',
		's5.b0': 'b44459cc78b71aaf',
		's6.heading': 'b26ffa9d3d25af83',
		's6.b0.i0': '5aa5f4e57b72adfb',
		's6.b0.i1': '323f02b7ad1e355d',
		's6.b0.i2': 'ce8974750a19dc0f',
		's6.b1': '1a0778a6029af8ae',
		's7.heading': '8cfcf517e30f6408',
		's7.b0': 'e103d457341fcf30',
	},
};
