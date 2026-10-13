import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'record-your-first-run',
	source: '9587d8580082759d',
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
};
