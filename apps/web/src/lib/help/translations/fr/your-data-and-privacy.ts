import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'your-data-and-privacy',
	title: 'Vos données et votre vie privée',
	summary: 'Voyez ce que les autres peuvent voir, choisissez qui voit vos nouvelles courses, téléchargez tout ce que nous détenons sur vous et supprimez votre compte.',
	sections: [
		{
			heading: 'Ce que les autres peuvent voir',
			blocks: [
				{
					type: 'list',
					items: [
						'Votre page de profil, avec votre nom affiché, votre photo, vos nombres d\'abonnés et vos courses publiques, peut être ouverte par toute personne disposant de son lien.',
						'Les courses que vous rendez publiques apparaissent sur votre profil et dans le fil. Les courses privées ne sont visibles que par vous.',
						'Votre appartenance à un club public, et tout ce que vous y publiez, peut être vu par les personnes qui peuvent voir le club.',
						'Tant que vous partagez un lien en direct, la course en cours peut être vue par toute personne disposant du lien.',
					],
				},
				{
					type: 'p',
					text: 'Les zones de confidentialité masquent le début et la fin de vos traces partout où quelqu\'un d\'autre les voit. Voir [[guide:privacy-zones|Masquer votre domicile avec les zones de confidentialité]].',
				},
			],
		},
		{
			heading: 'Choisir qui voit vos nouvelles courses',
			blocks: [
				{
					type: 'steps',
					items: [
						'Sur le web, ouvrez [[route:/settings/privacy|Confidentialité et partage]] dans les Paramètres et choisissez une **Visibilité par défaut des nouvelles courses**. Dans l\'app mobile, il s\'agit de **Confidentialité par défaut des courses** sous **Préférences** dans l\'onglet **Vous**.',
						'Pour modifier une seule course plus tard, ouvrez-la et utilisez **Rendre public** ou **Rendre privé**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Seul **Public** rend les nouvelles courses visibles par les autres. Les courses n\'ont pas encore de réglage réservé aux abonnés : choisir les abonnés par défaut garde donc vos nouvelles courses privées, et vos abonnés ne les verront pas.',
				},
				{
					type: 'list',
					items: [
						'**M\'afficher dans la recherche par nom** : désactivez-le pour que votre compte n\'apparaisse pas dans les recherches par nom. Votre profil et vos courses publiques peuvent toujours être ouverts par toute personne qui a le lien.',
						'**M\'afficher dans Coureurs à proximité**, là où il est proposé : désactivé par défaut. Une fois activé, les coureurs proches de la zone que vous avez définie peuvent vous trouver. Seule une zone approximative est enregistrée, jamais votre position en direct.',
					],
				},
			],
		},
		{
			heading: 'Télécharger vos données',
			blocks: [
				{
					type: 'p',
					text: 'Sur le web, ouvrez **Compte** dans les Paramètres. L\'app mobile propose les mêmes options sous **Compte** dans l\'onglet **Vous**.',
				},
				{
					type: 'list',
					items: [
						'**Télécharger l\'archive complète du compte** (sur le téléphone, **Export du compte**) : tout ce que nous détenons sur vous, y compris les conversations avec le coach, les messages, les intégrations et les contacts de sécurité, dans un seul zip. Elle est générée sur notre serveur : vous pouvez donc fermer la page et revenir la chercher. Un export terminé est conservé 7 jours.',
						'**Télécharger la sauvegarde complète** (sur le téléphone, **Sauvegarde complète**) : chaque course avec sa trace GPS, ainsi que vos itinéraires, votre profil et vos préférences, dans un fichier que vous pourrez restaurer plus tard avec **Restaurer depuis une sauvegarde**.',
						'**Export cloud (zip GPX)** : un fichier GPX par course, avec la fréquence cardiaque, prêt à importer dans d\'autres apps. Les comptes gratuits peuvent exporter deux fois par heure, les comptes Pro huit fois.',
						'**Exporter toutes les courses (CSV)** (sur le téléphone, **Exporter les courses en CSV**) : une ligne par course pour un tableur, sans les traces GPS.',
					],
				},
			],
		},
		{
			heading: 'Supprimer votre compte',
			blocks: [
				{
					type: 'steps',
					items: [
						'Téléchargez d\'abord tout ce que vous voulez garder. La suppression est irréversible.',
						'Sur le web, ouvrez **Compte** dans les Paramètres et sélectionnez **Supprimer le compte** sous **Zone de danger**. Dans l\'app mobile, ouvrez **Compte** dans l\'onglet **Vous** et touchez **Supprimer le compte**.',
						'Saisissez SUPPRIMER pour confirmer, puis sélectionnez **Supprimer mon compte** sur le web ou **Supprimer** dans l\'app.',
					],
				},
				{
					type: 'p',
					text: 'Cela supprime définitivement votre compte, vos courses, vos itinéraires, vos traces, vos adhésions à des clubs et vos préférences de nos serveurs. Sur un téléphone, les courses stockées sur l\'appareil lui-même y restent jusqu\'à ce que vous vous connectiez avec un autre compte ou que vous supprimiez l\'app.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Vous n\'arrivez pas à accéder à l\'app ? [[route:/delete-account|Supprimer votre compte]] explique comment demander la suppression sans elle.',
				},
			],
		},
	],
	sources: {
		title: 'd180bf422ce3bba9',
		summary: '2b4cc5410b0eb4b6',
		's0.heading': '4158a516fb61f91b',
		's0.b0.i0': '6b0cdb0395bd2c4b',
		's0.b0.i1': '9a700fce5a4094fc',
		's0.b0.i2': 'dc76446c63a054d2',
		's0.b0.i3': '483ea8dba216e43c',
		's0.b1': '0bbe7c39a03a9a09',
		's1.heading': 'ac353e580fc0908f',
		's1.b0.i0': '7b3a2d8b5b822576',
		's1.b0.i1': '1c68d368acdbf5ae',
		's1.b1': 'bdd9bb09bf384ad6',
		's1.b2.i0': 'aab065e45ac34e20',
		's1.b2.i1': 'af52470fc68dc9fb',
		's2.heading': 'fdbb4b35c4c483a4',
		's2.b0': 'c99f3ecf63b1a523',
		's2.b1.i0': '8c4857178e5dd3a5',
		's2.b1.i1': 'f4e6bebd7857fbbf',
		's2.b1.i2': 'c951ce9065ab0b67',
		's2.b1.i3': '6411af4fff4994ab',
		's3.heading': '7ab60595358e5d64',
		's3.b0.i0': '1ff19ec591d3e32c',
		's3.b0.i1': '4875a916b34863e4',
		's3.b0.i2': '830592d994cabb71',
		's3.b1': '28c0738abf26e30b',
		's3.b2': '4abf7820527a0449',
	},
};
