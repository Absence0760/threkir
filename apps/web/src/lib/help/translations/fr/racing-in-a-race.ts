import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'racing-in-a-race',
	title: 'Participer à une course en direct',
	summary: 'Inscrivez-vous, choisissez votre parcours, lancez l\'enregistrement avant la ligne de départ et laissez votre téléphone ou votre montre vous chronométrer de la ligne de départ à la ligne d\'arrivée.',
	sections: [
		{
			heading: 'Quels appareils peuvent participer',
			blocks: [
				{
					type: 'list',
					items: [
						'App Android : prise en charge complète. Elle affiche le bandeau de course, envoie votre position en direct et vous chronomètre par les lignes de départ et d\'arrivée.',
						'App iPhone : elle exécute le même code qu\'Android, mais n\'a pas encore été testée sur iPhone lors d\'une vraie course.',
						'Montre Wear OS : prise en charge complète au poignet, y compris le chronométrage par les lignes. L\'inscription et le choix du parcours se font toujours sur le web ou le téléphone.',
						'Apple Watch : prise en charge préliminaire seulement. Elle affiche le bandeau de course, envoie votre position et transmet votre temps via votre iPhone, mais elle ne détecte pas les lignes de départ et d\'arrivée : elle n\'a donc pas d\'arrivée automatique, et elle n\'a pas fait ses preuves lors d\'une vraie course. Gardez votre téléphone sur vous en secours, ou rechronométrez ensuite votre résultat à partir de votre tracé sur le web.',
						'Web : servez-vous-en pour vous inscrire, choisir un parcours, consulter les résultats et rechronométrer un résultat à partir du tracé d\'une course enregistrée. Un navigateur ne peut pas enregistrer de course.',
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
						'S\'il y a plusieurs parcours, choisissez le vôtre dans **Votre parcours** sur le web. Dans l\'app mobile, on vous demande **Choisissez votre parcours** quand vous touchez **Je viens**.',
						'Touchez **Je participe**. Seule une inscription **Je participe** reçoit les alertes de course sur votre appareil ; **Peut-être** ne les reçoit pas.',
					],
				},
				{
					type: 'p',
					text: 'Vous avez changé d\'avis ? Sur le web, choisissez un autre parcours dans **Votre parcours** (vous verrez « Parcours mis à jour. »). Dans l\'app mobile, touchez **Changer de parcours**. Fixez votre parcours avant de lancer l\'enregistrement : votre téléphone ou votre montre le lit au début de l\'enregistrement de la course, et votre résultat va au classement de ce parcours.',
				},
			],
		},
		{
			heading: 'Course armée et course en direct',
			blocks: [
				{
					type: 'p',
					text: 'Quand l\'organisateur arme la course, l\'onglet Courir de l\'app mobile affiche **Course armée** avec « en attente du GO ». La montre Wear OS affiche « COURSE ARMÉE » au-dessus de son bouton Démarrer. Quand l\'organisateur donne le GO, cela devient **Course EN DIRECT** (« COURSE EN DIRECT » sur la montre) avec le temps écoulé et « touchez Démarrer ».',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Votre téléphone ou votre montre ne démarre pas l\'enregistrement tout seul : appuyez vous-même sur Démarrer, avant d\'atteindre la ligne de départ. Vous pouvez démarrer pendant que la course affiche **Course armée**, ou dès que vous voyez **Course EN DIRECT**. Un enregistrement lancé en avance est rattaché à la course au GO, sur le téléphone comme sur une montre Wear OS.',
				},
				{
					type: 'p',
					text: 'L\'app mobile recherche les courses auxquelles vous avez répondu **Je viens** et qui commencent dans la journée qui suit. Si le bandeau tarde à apparaître, gardez l\'app ouverte sur l\'onglet Courir pendant une minute.',
				},
			],
		},
		{
			heading: 'Franchir la ligne de départ',
			blocks: [
				{
					type: 'p',
					text: 'Quand votre parcours a une ligne de départ, l\'écran Courir indique à quelle distance elle se trouve, par exemple « 120 m jusqu\'à la ligne de départ ». Traversez-la dans le sens du parcours. Après le GO, votre téléphone ou votre montre Wear OS vibre alors, annonce « Ligne de départ franchie, chrono lancé » si les annonces vocales sont activées, et votre temps puce court à partir de cet instant.',
				},
				{
					type: 'list',
					items: [
						'Vous avez déjà dépassé la ligne de départ quand le GO retentit ? Votre départ est le GO lui-même.',
						'Franchir la ligne avant le GO, par exemple pendant l\'échauffement, ne compte pas. Après le GO, votre départ compte une fois que vous êtes à environ 50 m sur le parcours sans être repassé par la ligne.',
						'Si votre téléphone ou votre montre ne vous voit jamais franchir la ligne de départ, votre temps puce court plutôt à partir du moment où vous avez appuyé sur Démarrer.',
					],
				},
			],
		},
		{
			heading: 'Arrivée automatique',
			blocks: [
				{
					type: 'p',
					text: 'Vous n\'avez rien à appuyer à l\'arrivée. Quand votre parcours a une ligne d\'arrivée, votre téléphone ou votre montre Wear OS enregistre votre arrivée à l\'instant où vous la traversez dans le sens du parcours, une fois que vous avez couvert une part suffisante du parcours : 60 % de sa distance depuis votre franchissement de la ligne de départ, ou 90 % si aucun franchissement de la ligne de départ n\'a été détecté. Cela évite qu\'un parcours en boucle, qui part de l\'endroit où il arrive, enregistre votre arrivée dès le départ.',
				},
				{
					type: 'p',
					text: 'Passer à côté de la ligne d\'arrivée sur un chemin qui la longe ne compte pas, car vous ne la traversez jamais. Votre temps est pris à l\'instant où vous avez franchi la ligne. Le téléphone vibre et affiche « Arrivée ! » avec votre temps officiel.',
				},
				{
					type: 'p',
					text: 'Un parcours avec un point d\'arrivée mais sans ligne d\'arrivée garde l\'ancienne règle : votre arrivée est enregistrée une fois que vous êtes à moins de 30 m de l\'arrivée et avez couvert 90 % du parcours, chronométrée au moment où vous en étiez le plus proche. Sur un parcours avec une ligne d\'arrivée, ce cercle de 30 m ne compte que si vous appuyez sur Arrêter ou **Terminer la course** à l\'intérieur.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Il n\'y a pas d\'arrivée automatique si votre parcours n\'a pas de distance, n\'a ni ligne d\'arrivée ni point d\'arrivée, ou a un itinéraire qui franchit sa propre ligne d\'arrivée avant la fin, comme un parcours en tours. Utilisez Arrêter, puis **Terminer la course** quand vous franchissez la ligne.',
				},
			],
		},
		{
			heading: 'Pas terminé ? Reprendre',
			blocks: [
				{
					type: 'p',
					text: 'Une arrivée par la ligne est envoyée immédiatement et votre enregistrement se met en pause. Pendant les 60 secondes qui suivent, l\'écran Courir propose **Pas terminé ? Reprendre**, sur le téléphone comme sur une montre Wear OS. Si vous n\'avez pas terminé, par exemple parce que vous avez franchi la ligne trop tôt pendant un tour, touchez-le : votre résultat est retiré et l\'enregistrement continue. Si vous ne faites rien, l\'enregistrement s\'arrête et le résultat est maintenu.',
				},
				{
					type: 'p',
					text: 'Après avoir annulé une arrivée, terminez le reste de la course à la main : touchez Arrêter, puis **Terminer la course**, quand vous terminez vraiment. Si l\'app redémarre entre-temps, elle surveille de nouveau la ligne d\'arrivée, mais ne compte jamais l\'arrivée que vous avez annulée.',
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
						'Le **Temps puce** court de votre franchissement de la ligne de départ jusqu\'à votre arrivée. Si aucun franchissement de la ligne de départ n\'a été détecté, il court à partir du moment où vous avez appuyé sur Démarrer, ou à partir du GO si vous avez appuyé sur Démarrer plus tôt. Il n\'est jamais plus long que votre temps officiel.',
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
		'title': '3ce73ee9613bf595',
		'summary': '8a84191c960f3189',
		's0.heading': 'ac0fdba8f9fafc40',
		's0.b0.i0': '5f9d1c45bcbbfb31',
		's0.b0.i1': 'c4096345432d33e6',
		's0.b0.i2': '547cdcc69e247581',
		's0.b0.i3': 'f068efe69456ba52',
		's0.b0.i4': '13822228d183e2b0',
		's1.heading': 'f00c55d7857a6dce',
		's1.b0.i0': '30eeadd878d7b098',
		's1.b0.i1': '525a552fd753b987',
		's1.b0.i2': '9efc1bb52d90e6ef',
		's1.b1': '55c32b3a7d7a241c',
		's2.heading': 'ed31d49e898938c8',
		's2.b0': 'f4ff1ecc36a2cf8e',
		's2.b1': 'b77e8bc9d60c9032',
		's2.b2': 'ddeff25fbc81b659',
		's3.heading': '3a0b0b0d9f43041c',
		's3.b0': '521195c2168d7fda',
		's3.b1.i0': '90b0261b0ce9c3f1',
		's3.b1.i1': 'a8d5dd7d6540cf62',
		's3.b1.i2': '8984cdb2a3694851',
		's4.heading': 'b1c0468dde456524',
		's4.b0': '900f305519a8032c',
		's4.b1': '32f9e651e83644d2',
		's4.b2': 'b39f1ce0d4a09d1a',
		's4.b3': '0e408636f1230c3b',
		's5.heading': 'bfa00064941be0cc',
		's5.b0': '86c65402c413b22d',
		's5.b1': 'a71d2963bd840180',
		's6.heading': '5df934589d491767',
		's6.b0': 'f1a6d8c09124a7d8',
		's6.b1.i0': '7a35b26309af9c5b',
		's6.b1.i1': 'f2cbc2dc9b04ff5b',
		's6.b1.i2': '630eba7ef0538b75',
		's6.b2': 'a0e378aecf393dda',
		's6.b3': 'b99b4c432279d3ea',
		's7.heading': '19cee1ff0ce4a9e3',
		's7.b0': 'b44459cc78b71aaf',
		's8.heading': 'b26ffa9d3d25af83',
		's8.b0.i0': '5aa5f4e57b72adfb',
		's8.b0.i1': '43b664e01ad5869b',
		's8.b0.i2': 'ce8974750a19dc0f',
		's8.b1': '1a0778a6029af8ae',
		's9.heading': '8cfcf517e30f6408',
		's9.b0': 'e103d457341fcf30',
	},
};
