import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'adjust-a-plan-with-ai',
	title: 'Ajuster un plan d\'entraînement avec l\'IA',
	summary: 'Décrivez une modification de votre plan avec vos propres mots, vérifiez chaque changement proposé et n\'enregistrez que si vous êtes d\'accord.',
	sections: [
		{
			heading: 'Ce que l\'IA peut modifier',
			blocks: [
				{
					type: 'p',
					text: 'Ajuster avec l\'IA transforme une demande comme *déplace ma sortie longue au samedi* ou *allège la semaine prochaine* en modifications d\'un plan que vous avez enregistré. Elle peut déplacer une séance vers un autre jour de la même semaine, échanger deux jours, augmenter ou réduire un peu une semaine, transformer une semaine en semaine de récupération, ou sauter une séance.',
				},
				{
					type: 'p',
					text: 'Ce sont les règles de plan de Threkir qui appliquent chaque modification. L\'IA n\'écrit jamais une séance, une distance ou une allure : une demande comme *ajoute une séance de côtes* reçoit donc une note indiquant que ce n\'est pas possible. Pour tout le reste, utilisez **Modifier le plan**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ajuster avec l\'IA n\'existe que sur le web et n\'est peut-être pas encore activé. Si **Ajuster avec l\'IA** n\'apparaît pas sous **Ajuster le plan**, la fonction n\'est pas disponible pour vous.',
				},
			],
		},
		{
			heading: 'Demander une modification',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez votre plan sur le web et sélectionnez **Ajuster le plan**.',
						'Choisissez **Ajuster avec l\'IA**.',
						'Tapez ce que vous voulez changer, puis sélectionnez **Proposer des modifications**.',
						'Lisez les **Modifications proposées** : chaque séance déplacée, sautée ou allégée, et chaque objectif hebdomadaire modifié, avant et après.',
						'Sélectionnez **Appliquer les modifications proposées par l\'IA** pour les enregistrer. Tant que vous ne l\'avez pas fait, rien n\'a changé dans votre plan ; sélectionnez **Annuler** pour le laisser tel quel.',
					],
				},
			],
		},
		{
			heading: 'Vérifications de sécurité avant l\'enregistrement',
			blocks: [
				{
					type: 'list',
					items: [
						'Des modifications qui feraient passer une semaine dans la zone de risque élevé de blessure par rapport à votre entraînement récent ne peuvent pas être appliquées. La page indique de quelle semaine il s\'agit.',
						'Si les modifications rendent une semaine plus dure que ce que votre entraînement récent permet, ou placent deux séances difficiles sur deux jours consécutifs, on vous demande **Appliquer des modifications plus dures ?** et vous devez choisir **Appliquer quand même**.',
						'Une proposition qui ne pouvait pas être appliquée sans risque est écartée, et la page vous le signale.',
					],
				},
			],
		},
		{
			heading: 'Ce que la fonction utilise',
			blocks: [
				{
					type: 'list',
					items: [
						'Chaque demande utilise l\'un de vos messages quotidiens du Coach IA, le même quota que le Coach.',
						'Elle nécessite la dernière version de l\'avis sur l\'IA. Si on vous demande de l\'accepter, sélectionnez **La consulter dans les Réglages** et acceptez-la là.',
						'Seules les séances à venir de votre plan et la modification que vous avez tapée sont envoyées à l\'IA.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Vous pouvez aussi demander au Coach de modifier votre plan. Il répond par un lien qui ouvre Ajuster avec l\'IA avec votre demande déjà remplie.',
				},
			],
		},
	],
	sources: {
		title: '3430390db6cef427',
		summary: '0b8f143261af9bcc',
		's0.heading': '44fa39d8b77c49be',
		's0.b0': '38fcc465ef1aec71',
		's0.b1': '7e6eec922334abd2',
		's0.b2': 'ca366aa955882170',
		's1.heading': 'f445fc4ffc97bebf',
		's1.b0.i0': '62be50b834eee366',
		's1.b0.i1': '490a29939b6ffad0',
		's1.b0.i2': '8dd005960648769c',
		's1.b0.i3': '6b71202d85d1ca61',
		's1.b0.i4': '1372a2a63c642a43',
		's2.heading': 'd9ef6a00bed5abfb',
		's2.b0.i0': '5b077f2018bffd38',
		's2.b0.i1': '2aae15cab49e816a',
		's2.b0.i2': 'aa84c731a647d1f3',
		's3.heading': '7e05806066a320c6',
		's3.b0.i0': '62c07e209d9ce339',
		's3.b0.i1': '1418c266b519f9d9',
		's3.b0.i2': '5de71e71f15f24a2',
		's3.b1': '12d00dbd647acb4c',
	},
};
