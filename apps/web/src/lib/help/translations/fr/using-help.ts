import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'using-help',
	source: 'a9e53ac06c08edd3',
	title: 'Trouver de l\'aide dans l\'app',
	summary: 'Où se trouvent les guides d\'aide, comment les rechercher et comment passer d\'un écran au guide qui l\'explique.',
	sections: [
		{
			heading: 'Ouvrir l\'aide',
			blocks: [
				{
					type: 'steps',
					items: [
						'Sélectionnez votre nom en bas de la barre latérale. Dans une fenêtre étroite, la barre latérale se réduit à des icônes : sélectionnez alors l\'avatar rond avec votre initiale.',
						'Choisissez **Aide** dans le menu qui s\'ouvre.',
					],
				},
				{
					type: 'p',
					text: 'La page de sommaire liste tous les guides par thème. Les filtres sous **Afficher les guides pour** restreignent la liste aux guides écrits pour vous, comme **Organisateurs** ou **Spectateurs** ; **Tous** affiche de nouveau l\'ensemble.',
				},
			],
		},
		{
			heading: 'Rechercher dans les guides',
			blocks: [
				{
					type: 'p',
					text: 'Saisissez un ou deux mots dans **Rechercher dans les guides** en haut de [[route:/help|Aide]] et appuyez sur **Rechercher**. Les guides dont le titre contient vos mots apparaissent en premier, puis ceux qui les mentionnent dans leur résumé, puis les autres.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Les majuscules et les accents n\'ont pas d\'importance : *cafe* trouve donc *Café*. Chaque mot saisi doit figurer quelque part dans un guide pour que celui-ci soit listé.',
				},
			],
		},
		{
			heading: 'L\'aide depuis l\'écran où vous êtes',
			blocks: [
				{
					type: 'p',
					text: 'Un écran qui dispose d\'un guide affiche un lien **Comment ça marche** près de son titre. Il ouvre le guide de cet écran ; si plusieurs guides le couvrent, il ouvre une courte liste pour choisir.',
				},
				{
					type: 'p',
					text: 'Certaines cartes et certains réglages portent un petit bouton rond *i*. Il explique la fonctionnalité en une phrase ou deux, et quand un guide va plus loin, il se termine par **Lire le guide**.',
				},
			],
		},
		{
			heading: 'Lire un guide',
			blocks: [
				{
					type: 'list',
					items: [
						'Les badges sous le titre indiquent à quelles apps le guide s\'applique et s\'il vous faut quelque chose au préalable, comme Pro ou un rôle d\'admin de club.',
						'**Sur cette page** liste les sections d\'un guide long et vous amène à celle que vous choisissez.',
						'**Guides associés**, à la fin, indique ce dont vous aurez probablement besoin ensuite.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Les guides s\'affichent dans la langue de l\'app. Un guide qui n\'a pas encore été traduit dans cette langue s\'affiche en anglais, avec une note en haut qui le signale.',
				},
			],
		},
	],
};
