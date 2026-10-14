import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'record-your-first-run',
	title: 'Enregistrer votre première course',
	summary: 'Démarrez une course sur votre téléphone, mettez-la en pause et arrêtez-la sans risque, obtenez un bon signal GPS et voyez ce qui est enregistré ensuite.',
	sections: [
		{
			heading: 'Démarrer l\'enregistrement',
			blocks: [
				{
					type: 'p',
					text: 'Les courses s\'enregistrent dans l\'app mobile ou sur une montre. L\'app web affiche vos courses mais ne peut pas en enregistrer.',
				},
				{
					type: 'steps',
					items: [
						'Touchez le grand bouton au milieu de la barre du bas. Il indique **Courir**, ou **Ajouter** si vous avez activé la muscu ou la nutrition, auquel cas choisissez **Enregistrer une course**.',
						'Touchez **DÉMARRER**. La première fois, votre téléphone demande l\'accès à la localisation : autorisez-le, sinon la course n\'enregistre que le temps, sans distance ni carte.',
						'Un compte à rebours de trois secondes s\'écoule pendant que le GPS se prépare, puis le chrono démarre.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Sur Android, choisissez **Toujours autoriser** pour la localisation. Si l\'accès n\'est accordé que lorsque l\'app est ouverte, la distance parcourue écran éteint n\'est pas comptée, même si le chrono continue de tourner.',
				},
				{
					type: 'illustration',
					id: 'record-your-first-run',
					alt: 'Un téléphone doté d\'un grand bouton de démarrage rond, qui capte le signal GPS d\'un satellite dans le ciel.',
				},
			],
		},
		{
			heading: 'Pause et arrêt',
			blocks: [
				{
					type: 'p',
					text: 'Il n\'y a pas de pause automatique : le chrono tourne jusqu\'à ce que vous le mettiez en pause. Utilisez le bouton pause pour un arrêt que vous voulez exclure de votre temps, et le bouton reprendre pour continuer.',
				},
				{
					type: 'p',
					text: 'Attendre à un passage piéton sans mettre en pause ne pose aucun problème. Après la course, le temps **En mouvement** exclut les moments où vous étiez à l\'arrêt, et votre allure est calculée sur le temps en mouvement.',
				},
				{
					type: 'steps',
					items: [
						'Pour terminer, maintenez le bouton stop appuyé. L\'indication affiche **Maintenir pour arrêter**, pour qu\'un appui involontaire dans votre poche ne termine pas la course.',
						'Le récapitulatif **Course terminée** affiche votre distance, le **Temps**, le temps **En mouvement**, l\'allure et toutes les autres statistiques mesurées par votre téléphone.',
						'Touchez **Terminé** pour revenir à l\'écran de départ.',
					],
				},
			],
		},
		{
			heading: 'Obtenir un bon signal GPS',
			blocks: [
				{
					type: 'list',
					items: [
						'Partez à l\'extérieur, loin des grands immeubles et des arbres touffus, pour que le compte à rebours ait une vue dégagée sur le ciel.',
						'Si vous voyez **Signal GPS perdu — sortez à découvert**, continuez : le chrono tourne toujours et la distance reprend dès le retour du signal.',
						'**GPS faible — distance en pause** signifie que votre position est trop incertaine pour être comptée. La distance reprend dès que le signal s\'améliore.',
						'Laissez les services de localisation activés et l\'économie de batterie désactivée pour l\'app, afin que votre téléphone n\'arrête pas l\'enregistrement en arrière-plan.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si l\'app se ferme en pleine course, rouvrez-la : la question **Reprendre votre course ?** s\'affiche et vous pouvez reprendre, terminer maintenant ou supprimer la course.',
				},
			],
		},
		{
			heading: 'Ce qui est enregistré',
			blocks: [
				{
					type: 'p',
					text: 'À l\'arrêt, la course est d\'abord enregistrée sur votre téléphone, puis envoyée sur votre compte. Le récapitulatif affiche **Synchronisé** une fois qu\'elle est en sécurité dans le cloud, ou **Enregistré hors ligne.** si vous êtes déconnecté. Une course qui n\'a pas pu être envoyée reste sur le téléphone et l\'envoi est réessayé plus tard.',
				},
				{
					type: 'list',
					items: [
						'Distance, temps écoulé, temps en mouvement et allure.',
						'Votre tracé GPS, qui sert à dessiner la carte et les splits.',
						'Altitude, pas, et fréquence cardiaque si vous avez appairé une ceinture cardio.',
					],
				},
				{
					type: 'p',
					text: 'Qui peut voir la course dépend de votre réglage **Confidentialité par défaut des courses**, que vous pouvez ensuite modifier pour n\'importe quelle course. Pour masquer l\'endroit où vous habitez, configurez des [[guide:privacy-zones|zones de confidentialité]] avant de partager quoi que ce soit.',
				},
			],
		},
	],
	sources: {
		title: '70047f50b01f1af6',
		summary: 'dc170443668c395f',
		's0.heading': '30756af0134e4bf1',
		's0.b0': '6dc07a2b5e601838',
		's0.b1.i0': 'a7632a8cd2567c2c',
		's0.b1.i1': '68b860679cd99712',
		's0.b1.i2': 'a406181fe0c90b54',
		's0.b2': 'b93825fb9981ec39',
		's1.heading': '7c0f775fc550ae67',
		's1.b0': '7cdb0afab0e6c855',
		's1.b1': '1514c09a3d983d9e',
		's1.b2.i0': '2c86f71499d052af',
		's1.b2.i1': 'a2b9c26b2835d1ac',
		's1.b2.i2': 'c28a30ef42432d2f',
		's2.heading': 'cb9aedf1a5764367',
		's2.b0.i0': '35ba6295ed45225d',
		's2.b0.i1': '44f804dddcf3049e',
		's2.b0.i2': 'b8c55726529e022b',
		's2.b0.i3': '514cfcccb3fc6f5e',
		's2.b1': '2f0d094e06e813c3',
		's3.heading': 'f075ba7c6636fa8a',
		's3.b0': 'ef5a53403410399c',
		's3.b1.i0': 'ec005f0ead60e9e0',
		's3.b1.i1': 'e0fd699761f32367',
		's3.b1.i2': '1d33b3ee8d0be1b8',
		's3.b2': 'a8054fd15c256c3c',
		's0.b3': '21307fc19189cc42',
	},
};
