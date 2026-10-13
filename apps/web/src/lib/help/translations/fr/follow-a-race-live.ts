import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'follow-a-race-live',
	source: 'e0211e5c39173f51',
	title: 'Suivre une course en direct',
	summary: 'Suivez une course en temps réel sur sa page en direct : les coureurs sur une carte, qui est sur le parcours et qui a terminé sur chaque parcours.',
	sections: [
		{
			heading: 'Ouvrir la page en direct',
			blocks: [
				{
					type: 'p',
					text: 'L\'organisateur partage un lien vers la page en direct de la course ; sinon, si vous pouvez voir l\'événement, ouvrez-le et choisissez **Vue spectateur**. Vous n\'avez pas besoin de compte. Si l\'événement est **Membres uniquement**, vous devez être membre du club pour le voir.',
				},
				{
					type: 'p',
					text: 'Le haut de la page indique l\'état de la course :',
				},
				{
					type: 'list',
					items: [
						'**Avant la course** : l\'organisateur n\'a pas encore armé le chrono de la course.',
						'**Armé** : le chrono est armé et attend le départ.',
						'**En cours** : la course est lancée, avec le temps écoulé.',
						'**Terminé** : la course est finie.',
						'**Annulé** : l\'organisateur a annulé la course.',
					],
				},
			],
		},
		{
			heading: 'La carte',
			blocks: [
				{
					type: 'p',
					text: 'Sauf si vous avez déjà autorisé les cartes dans vos paramètres de cookies, la carte reste désactivée jusqu\'à ce que vous choisissiez **Charger la carte**, car son chargement envoie votre adresse IP à notre fournisseur de tuiles cartographiques. Une fois la carte chargée, chaque coureur est un point de couleur suivi d\'une courte trace de son parcours récent. Les téléphones et montres des coureurs envoient une position environ toutes les 10 secondes, et la page se met à jour d\'elle-même.',
				},
			],
		},
		{
			heading: 'Sur le parcours',
			blocks: [
				{
					type: 'p',
					text: 'Le classement **Sur le parcours** liste chaque coureur qui a envoyé une position, du plus avancé au moins avancé, avec la distance, l\'allure et le temps écoulé ; il y a un classement par parcours quand la course en compte plusieurs. Chaque ligne indique aussi depuis combien de temps elle a été mise à jour.',
				},
				{
					type: 'p',
					text: 'Il n\'y a pas d\'étiquette « en pause » distincte. Un coureur qui s\'est arrêté (pour refaire un lacet, à un ravitaillement ou parce qu\'il a mis son enregistrement en pause) ou qui a perdu le signal cesse simplement d\'être mis à jour. Après environ 90 secondes sans mise à jour, sa ligne est marquée **RETARDÉ**. Cela ne veut pas dire qu\'il y a un problème ; souvent, il n\'y a simplement pas de réseau.',
				},
			],
		},
		{
			heading: 'Arrivées',
			blocks: [
				{
					type: 'p',
					text: 'Les coureurs arrivés apparaissent sous **Terminé** au fur et à mesure que leurs résultats arrivent, avec un classement par parcours quand la course en compte plusieurs. Les coureurs qui n\'ont pas terminé sont listés sous **N\'a pas terminé**. Un résultat que l\'organisateur n\'a pas encore approuvé est marqué **En attente**.',
				},
				{
					type: 'p',
					text: 'La signification des temps et des badges est expliquée dans [[guide:race-results-explained|Comprendre les résultats de course]].',
				},
			],
		},
		{
			heading: 'Confidentialité',
			blocks: [
				{
					type: 'list',
					items: [
						'Les vrais noms des coureurs ne sont visibles que par les personnes liées à eux par un abonnement, dans un sens ou dans l\'autre. Tous les autres voient un pseudonyme anonyme, par exemple Runner #A1B2.',
						'Près de la zone de confidentialité d\'un coureur, sa position exacte est masquée. Vous voyez à la place **Vu pour la dernière fois près d\'ici · approximatif**, affiché sous la forme d\'un anneau vide plutôt que d\'un point.',
						'Les coureurs arrivés importés par l\'organisateur depuis une liste de dossards n\'ont pas de compte : ils gardent donc le nom saisi par l\'organisateur.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Toute personne qui a le lien peut suivre la course. Si vous participez et préférez ne pas être suivi en direct, parlez-en à l\'organisateur avant la course.',
				},
			],
		},
	],
};
