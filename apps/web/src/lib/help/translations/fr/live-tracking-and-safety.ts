import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'live-tracking-and-safety',
	source: 'a9b8d219fce642c1',
	title: 'Suivi en direct et contacts de sécurité',
	summary: 'Laissez quelqu\'un suivre votre course en direct, et faites prévenir par e-mail vos contacts de confiance quand vous terminez, ne donnez plus signe de vie ou n\'êtes pas rentré à l\'heure.',
	sections: [
		{
			heading: 'Partager un lien en direct',
			blocks: [
				{
					type: 'steps',
					items: [
						'Connectez-vous dans l\'app mobile. Un lien en direct ne fonctionne que pour un coureur connecté.',
						'Sur l\'écran de course, avant de démarrer, touchez **Partager le lien en direct** et envoyez-le avec n\'importe quelle app de votre téléphone.',
						'Touchez **DÉMARRER**. Le lien devient actif au début de la course.',
					],
				},
				{
					type: 'p',
					text: 'Toute personne qui a le lien peut l\'ouvrir dans un navigateur web et suivre votre position et vos statistiques, sans avoir besoin de compte. Les zones de confidentialité s\'appliquent toujours à la carte en direct.',
				},
				{
					type: 'p',
					text: 'Pendant le partage, un badge **En direct** s\'affiche sur l\'écran d\'enregistrement. Touchez-le pour **Repartager le lien**, **Arrêter le partage** ou définir une heure **Pas rentré à…**.',
				},
				{
					type: 'p',
					text: 'À la fin de la course, le lien n\'est plus mis à jour. Si vos courses ne sont normalement pas publiques, on vous demande s\'il faut **Garder publique** la course enregistrée pour les personnes qui ont le lien ; sinon, elle revient à la confidentialité habituelle de vos courses.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Pour partager chaque course sans avoir à y penser, activez **Partage en direct automatique** sous **Contacts de sécurité** dans l\'onglet **Vous**. Ce réglage ne s\'applique qu\'à ce téléphone, et la course en cours peut être vue par toute personne qui a le lien.',
				},
			],
		},
		{
			heading: 'Ajouter des contacts de sécurité',
			blocks: [
				{
					type: 'p',
					text: 'Un contact de sécurité est une personne de confiance, comme votre partenaire, un ami ou un membre de votre famille. Il reçoit un e-mail quand vous terminez une course, même privée, pour savoir que vous êtes bien rentré.',
				},
				{
					type: 'steps',
					items: [
						'Sur le web, ouvrez [[route:/settings/safety|Sécurité]] dans les Paramètres ; dans l\'app mobile, ouvrez **Contacts de sécurité** dans l\'onglet **Vous**.',
						'Saisissez son adresse dans **E-mail du contact**. Vous pouvez aussi ajouter un **Téléphone pour SMS (facultatif)** au format international, par exemple +447700900123.',
						'Sélectionnez **Ajouter un contact**. La personne reçoit un e-mail lui demandant de confirmer.',
						'Son statut affiche **En attente — confirmation requise** jusqu\'à ce qu\'elle accepte, puis **Confirmé**. Seuls les contacts confirmés sont alertés.',
					],
				},
				{
					type: 'p',
					text: 'Si quelqu\'un vous ajoute comme contact, la demande apparaît sous **Demandes pour vous**, où vous pouvez choisir **Confirmer** ou **Refuser**. Plus tard, sous **Vous êtes contact de sécurité**, vous pouvez changer la façon dont vous êtes alerté ou choisir **Me retirer**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Les alertes par e-mail sont toujours envoyées. Les SMS nécessitent en plus que le contact les accepte au moment de confirmer, et l\'envoi de SMS n\'est pas encore activé partout : ne comptez donc pas uniquement sur les SMS.',
				},
			],
		},
		{
			heading: 'Alertes quand quelque chose semble anormal',
			blocks: [
				{
					type: 'p',
					text: 'Ces alertes ne couvrent que les courses avec le partage en direct activé, car c\'est le lien en direct qui nous indique où vous êtes. Chaque contact reçoit au plus une alerte par course.',
				},
				{
					type: 'list',
					items: [
						'**Alerte de retard** : choisissez une durée sous **Alerter les contacts après un silence de** sur le web, ou **Alerter après un silence de** dans l\'app. Si votre course en direct n\'envoie rien pendant cette durée, vos contacts confirmés reçoivent votre lien en direct par e-mail. L\'alerte reste sur **Désactivé** tant que vous n\'avez pas choisi de durée.',
						'**Pas rentré à…** : pendant une course partagée en direct, touchez le badge **En direct** et choisissez l\'heure à laquelle vous pensez avoir terminé. Si la course est toujours en cours à ce moment-là, vos contacts sont alertés. L\'heure est conservée sur notre serveur : elle compte donc même si votre téléphone s\'éteint. Vous pouvez aussi la définir depuis votre propre page en direct sur le web.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Une perte de réseau ressemble à un silence, et une course terminée sans réseau peut encore déclencher une alerte tant qu\'elle n\'a pas été envoyée. L\'e-mail indique à vos contacts qu\'une perte de réseau est une cause possible.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Une alerte automatique à vos contacts quand vous quittez votre itinéraire prévu est développée mais pas encore activée. D\'ici là, le réglage **Alerte hors itinéraire** reste masqué.',
				},
			],
		},
		{
			heading: 'Avertissements hors itinéraire pendant la course',
			blocks: [
				{
					type: 'p',
					text: 'Si vous suivez un itinéraire enregistré, l\'écran de course vous avertit quand vous vous en écartez, en indiquant à quelle distance vous êtes, et peut l\'annoncer à voix haute si les annonces audio sont activées. Cet avertissement est pour vous ; il ne contacte personne.',
				},
			],
		},
	],
};
