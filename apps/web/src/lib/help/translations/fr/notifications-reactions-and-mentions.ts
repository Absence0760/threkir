import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'notifications-reactions-and-mentions',
	title: 'Réactions, mentions et vos notifications',
	summary: 'Réagissez aux courses, aimez des commentaires et mentionnez d\'autres coureurs, puis choisissez quelles notifications vous parviennent aussi par e-mail et sur votre téléphone.',
	sections: [
		{
			heading: 'Réagir, aimer et mentionner',
			blocks: [
				{
					type: 'list',
					items: [
						'Sur la course de quelqu\'un d\'autre, à côté des kudos, choisissez une réaction : **En feu**, **Solide**, **Champion**, **Bien joué** ou **Coucou**. Vous pouvez en laisser plusieurs, et choisir de nouveau une réaction la retire.',
						'Pour aimer un commentaire, choisissez le cœur à côté. Vous ne pouvez pas réagir à votre propre course ni aimer votre propre commentaire.',
						'Pour mentionner quelqu\'un dans un commentaire, tapez @ puis le début de son nom, et choisissez la personne dans la liste qui s\'affiche. Elle n\'est prévenue que si elle peut déjà voir la course et qu\'aucun de vous deux n\'a bloqué l\'autre.',
					],
				},
				{
					type: 'p',
					text: 'Les réactions et les j\'aime sur les commentaires s\'affichent sur la course elle-même. Les cartes du fil ne montrent toujours que le nombre de kudos et de commentaires.',
				},
			],
		},
		{
			heading: 'Où arrivent les notifications',
			blocks: [
				{
					type: 'p',
					text: 'Chaque notification arrive dans l\'app : sous la cloche sur le web, et dans l\'onglet **Notifications** de votre profil dans l\'app mobile. C\'est vous qui décidez si elle vous parvient aussi par e-mail ou sur votre téléphone.',
				},
			],
		},
		{
			heading: 'Choisir ce qui est envoyé par e-mail et en push',
			blocks: [
				{
					type: 'steps',
					items: [
						'Sur le web, ouvrez [[route:/settings/notifications|Notifications]] dans les Paramètres. Dans l\'app mobile, ouvrez **Préférences** dans l\'onglet **Vous** et faites défiler jusqu\'à **Notifications**.',
						'Réglez séparément **Notifications par e-mail** et **Notifications push**.',
					],
				},
				{
					type: 'list',
					items: [
						'**Importantes uniquement**, le réglage par défaut : ce que vous attendez ou ce qui change vos plans, comme les messages, les rappels et annulations d\'événements, une place réservée pour vous sur une liste d\'attente, les mentions, les demandes d\'abonnement et un export de données terminé.',
						'**Toutes** : les importantes, plus les notifications sociales comme les kudos, les commentaires, les nouveaux abonnés, les réactions et les j\'aime sur les commentaires.',
						'**Désactivées** : rien sur ce canal. L\'app affiche toujours tout.',
					],
				},
			],
		},
		{
			heading: 'Désactiver un seul type',
			blocks: [
				{
					type: 'p',
					text: 'Sur le web, la même page permet de couper certains types sans changer tout un canal : **Export de données prêt**, **Mentions**, **Réactions à mes courses**, **J\'aime sur mes commentaires** et **Demandes d\'abonnement**. Décochez-en un et il n\'est plus envoyé par e-mail ni en push, y compris sur votre téléphone, mais il apparaît toujours dans l\'app.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Ces cases ne font que couper. Les réactions et les j\'aime sur les commentaires ne sont envoyés que lorsqu\'un canal est réglé sur **Toutes**, et un canal réglé sur **Désactivées** reste muet quelles que soient les cases.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Les cases par type ne sont pour l\'instant disponibles que sur le web. L\'app mobile affiche les réglages e-mail et push.',
				},
			],
		},
	],
	sources: {
		title: 'e2dd210eef629161',
		summary: 'e3caa3dd4051e339',
		's0.heading': 'e9a0aa732a34f472',
		's0.b0.i0': '593bf97b7d4b2620',
		's0.b0.i1': '47c9a6dbdeb3921f',
		's0.b0.i2': '3f6f5a25189cef93',
		's0.b1': 'a9ec227602fcdf51',
		's1.heading': '074e9ceb824efc1f',
		's1.b0': '93884f29ad0c80fc',
		's2.heading': 'effb878df9e1a9ea',
		's2.b0.i0': '1c0dfd20d4a186e9',
		's2.b0.i1': '5a887c760fb14d6f',
		's2.b1.i0': '3adf3c1bbb3ad28d',
		's2.b1.i1': '20670a8e203c8f76',
		's2.b1.i2': '0e68d1c319340628',
		's3.heading': '99fb6c0af9167c4d',
		's3.b0': 'f6afa349950bc135',
		's3.b1': '17f7f798ca3f2b0d',
		's3.b2': '7471f8039fdd65e1',
	},
};
