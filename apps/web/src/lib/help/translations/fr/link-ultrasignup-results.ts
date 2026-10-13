import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'link-ultrasignup-results',
	title: 'Associer vos résultats UltraSignup',
	summary: 'Retrouvez votre profil UltraSignup par votre nom, confirmez quelle personne est vous, puis importez un résultat d\'ultra ou de trail depuis le calendrier des courses.',
	sections: [
		{
			heading: 'Avant de commencer',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'L\'import UltraSignup est disponible uniquement sur le web et reste désactivé tant qu\'il n\'a pas été activé. Si la carte UltraSignup est absente des Intégrations, ou affiche **L\'import UltraSignup n\'est pas encore disponible. parkrun et le collage manuel fonctionnent toujours.**, vous pouvez quand même ajouter un résultat en le collant dans le calendrier des courses.',
				},
				{
					type: 'p',
					text: 'UltraSignup gère les inscriptions et les résultats de nombreuses courses de trail et d\'ultra. Une fois votre profil associé, vous n\'avez plus jamais à saisir votre nom ou votre numéro de dossard pour importer un résultat.',
				},
			],
		},
		{
			heading: 'Associer votre profil',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez [[route:/settings/integrations|Intégrations]] dans les Paramètres et repérez la carte UltraSignup.',
						'Sous **Retrouver ton profil UltraSignup**, saisissez votre **Prénom** et votre **Nom** exactement comme lors de vos inscriptions aux courses, puis sélectionnez **Me trouver**.',
						'UltraSignup liste toutes les personnes qui portent ce nom. Servez-vous de l\'âge, du nombre de résultats et des courses les plus récentes de chacune pour vous repérer.',
						'Sous **Laquelle de ces personnes est toi ?**, sélectionnez **C\'est moi** sur votre ligne.',
					],
				},
				{
					type: 'p',
					text: 'La carte affiche maintenant **Associé en tant que** avec votre nom et votre numéro UltraSignup. Si vous avez choisi la mauvaise personne, sélectionnez **Dissocier** et recherchez à nouveau. Les courses déjà importées sont conservées quand vous dissociez votre profil.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si vous voyez **UltraSignup ne connaît personne sous ce nom. Vérifie l\'orthographe sous laquelle tu cours.**, essayez l\'orthographe exacte de vos inscriptions, y compris un éventuel deuxième prénom ou trait d\'union.',
				},
			],
		},
		{
			heading: 'Importer un résultat depuis le calendrier des courses',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez [[route:/races|Courses]] et trouvez la course à laquelle vous avez participé.',
						'Sélectionnez **Importer mon résultat**. L\'outil d\'import indique sous quelle identité il importe.',
						'Confirmez l\'import. Seul votre propre résultat pour cette course est récupéré, en se fondant sur l\'identifiant de course UltraSignup et la date de la course.',
					],
				},
				{
					type: 'p',
					text: 'Le résultat arrive sous forme de course enregistrée, avec votre temps officiel et vos classements. Si vous avez vous-même enregistré l\'épreuve, ouvrez plutôt cet enregistrement : quand il correspond à une épreuve du calendrier, il vous demande s\'il s\'agissait de celle-ci, et sélectionner **Importer le résultat** ajoute le résultat officiel à la course que vous avez déjà au lieu d\'en créer une deuxième.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Seuls les résultats d\'arrivée sont importés, et une course dont l\'identifiant ou la date ne correspond pas est ignorée plutôt que devinée. Très peu de courses UltraSignup figurent encore dans le calendrier, donc la vôtre n\'y est peut-être pas ; utilisez plutôt **Coller votre résultat** dans le calendrier des courses.',
				},
				{
					type: 'p',
					text: 'Si vous voyez **Associe d\'abord ton profil UltraSignup dans les Réglages, puis importe depuis ici.**, associez votre profil comme indiqué ci-dessus, puis revenez.',
				},
			],
		},
	],
	sources: {
		title: '1c3d3ccace74b014',
		summary: 'f2fca5922e80c09a',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '0c7ce54419de8a75',
		's0.b1': '44ce80029649ec21',
		's1.heading': '9585e27668c04a9f',
		's1.b0.i0': '5c97b00e1a40a36b',
		's1.b0.i1': 'c74c3876783d3d3e',
		's1.b0.i2': 'a2c9f8d1aa769e71',
		's1.b0.i3': '583ce1f06db5e7a3',
		's1.b1': '75c4a2aecaf4f626',
		's1.b2': 'a780f42937b826b1',
		's2.heading': '2beec2f1afabca9b',
		's2.b0.i0': 'b25aba40145c665f',
		's2.b0.i1': 'bd2e53852db627ea',
		's2.b0.i2': '6dce444ee6e264da',
		's2.b1': 'e5693507bec3f21c',
		's2.b2': '041b5d6a68e26cfe',
		's2.b3': '01220bce8ab2d8b5',
	},
};
