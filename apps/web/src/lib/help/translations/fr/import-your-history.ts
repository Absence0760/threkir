import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'import-your-history',
	title: 'Importer votre historique de course',
	summary: 'Importez vos anciennes courses depuis Strava, un export Garmin ou l\'app santé de votre téléphone, et sachez ce qu\'il advient des fichiers GPX.',
	sections: [
		{
			heading: 'Connecter Strava pour vos courses récentes et à venir',
			blocks: [
				{
					type: 'steps',
					items: [
						'Sur le web, ouvrez [[route:/settings/integrations|Intégrations]] dans les Paramètres et sélectionnez **Connecter** sur la carte Strava ; dans l\'app mobile, ouvrez **Intégrations** dans l\'onglet **Vous** et touchez Strava.',
						'Connectez-vous à Strava et autorisez l\'accès.',
						'Vos courses, marches et randonnées des 90 derniers jours sont copiées, et les nouvelles activités Strava suivent automatiquement.',
					],
				},
				{
					type: 'p',
					text: 'Sélectionnez **Synchroniser** pour relancer la récupération. Sur le web, **Jusqu\'où remonter** permet de remonter jusqu\'à un an en arrière.',
				},
				{
					type: 'illustration',
					id: 'import-your-history',
					alt: 'Les courses d\'une montre, d\'un compte connecté et d\'un fichier arrivent toutes dans une seule liste de courses.',
				},
			],
		},
		{
			heading: 'Importer toute votre archive Strava',
			blocks: [
				{
					type: 'p',
					text: 'Connecter Strava ne récupère que l\'activité récente. Pour des années d\'historique, utilisez un export de données Strava.',
				},
				{
					type: 'steps',
					items: [
						'Dans Strava, allez dans Paramètres, puis Mon compte, et demandez votre archive. Strava vous envoie par e-mail un lien vers un fichier zip.',
						'Sur le web, ouvrez [[route:/settings/integrations|Intégrations]], repérez **Import groupé depuis un export Strava** et sélectionnez **Choisir le zip d\'export Strava**. Dans l\'app mobile, ouvrez **Compte** dans l\'onglet **Vous**, puis **Importer depuis une autre app**, et touchez **Importer un ZIP Strava**.',
						'Attendez la fin de l\'import. Les courses que vous avez déjà, par exemple via votre connexion Strava, sont ignorées : vous pouvez donc le relancer sans risque.',
					],
				},
			],
		},
		{
			heading: 'Garmin et fichiers FIT',
			blocks: [
				{
					type: 'p',
					text: 'Une liaison automatique avec Garmin Connect n\'est pas encore disponible, car Garmin doit d\'abord l\'approuver. En attendant, vous pouvez importer des fichiers Garmin sur le web.',
				},
				{
					type: 'steps',
					items: [
						'Dans Garmin Connect, exportez une seule activité avec « Export Original », qui vous donne un fichier .fit, ou demandez l\'export complet de vos données depuis « Garmin Account Management ».',
						'Sur le web, ouvrez [[route:/settings/integrations|Intégrations]], repérez **Import groupé depuis un export Garmin** et sélectionnez **Choisir l\'export Garmin**.',
						'Choisissez le fichier .fit ou le zip. Les activités déjà importées sont ignorées.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Sur Android, les séances que votre app Garmin, Samsung ou Fitbit écrit dans Health Connect peuvent aussi arriver via **Importer depuis une autre app**. Sur iPhone, la même carte lit Apple Santé.',
				},
			],
		},
		{
			heading: 'GPX et autres fichiers isolés',
			blocks: [
				{
					type: 'p',
					text: 'Un fichier GPX, KML, KMZ, GeoJSON ou TCX isolé est importé comme un itinéraire à suivre, et non comme une course de votre historique. Ouvrez [[route:/routes|Itinéraires]] sur le web ou la liste des itinéraires dans l\'app, et importez-le là.',
				},
				{
					type: 'p',
					text: 'Les fichiers GPX et TCX contenus dans un zip d\'export Strava ou Garmin sont lus comme des courses : les imports groupés ci-dessus sont donc le moyen d\'ajouter un historique d\'activités GPX.',
				},
			],
		},
		{
			heading: 'Si quelque chose ne s\'importe pas',
			blocks: [
				{
					type: 'p',
					text: 'Quand des activités sont laissées de côté, l\'import les liste une par une avec la raison, par exemple une connexion interrompue ou un fichier illisible. Relancez l\'import pour les réessayer : tout ce qui est déjà arrivé est ignoré, donc rien n\'est dupliqué.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Les courses importées suivent la confidentialité par défaut de vos courses : vérifiez-la avant un gros import si vous ne voulez pas que des années de courses deviennent publiques d\'un coup. Voir [[guide:your-data-and-privacy|Vos données et votre vie privée]].',
				},
			],
		},
	],
	sources: {
		title: '078b29389d32808d',
		summary: '440ddd94eca0b542',
		's0.heading': '69858eb69781e59e',
		's0.b0.i0': '92767a2a2bf7c191',
		's0.b0.i1': '8c05e0ad16ddb8c2',
		's0.b0.i2': '828e8880f5239f1c',
		's0.b1': '4302ec5e7767e8ab',
		's1.heading': '8abf228027d2a4fd',
		's1.b0': 'cf7faaa4679e66f2',
		's1.b1.i0': '9e771e203c299ace',
		's1.b1.i1': 'a6d02ee139faa051',
		's1.b1.i2': '0212bc406356fd62',
		's2.heading': 'f3f586814898940a',
		's2.b0': '25c859eb00073fae',
		's2.b1.i0': 'f82bc798e8ec1b4e',
		's2.b1.i1': '21d706b389df8c6a',
		's2.b1.i2': '69a212e6bb305cfc',
		's2.b2': '7d501c5e8de3d96e',
		's3.heading': '8b42dffcf7f0d635',
		's3.b0': '0dba61c98d441dad',
		's3.b1': '5dbef244bd55926e',
		's4.heading': '35509c7701b9dabc',
		's4.b0': '26a0daac64b29af6',
		's4.b1': '69e6cfdbe0110cea',
		's0.b2': '38746dc95049a57f',
	},
};
