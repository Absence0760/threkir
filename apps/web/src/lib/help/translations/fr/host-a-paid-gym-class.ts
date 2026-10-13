import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'host-a-paid-gym-class',
	title: 'Organiser un cours payant de HIIT, de renforcement ou de bootcamp',
	summary: 'Planifiez un cours de muscu récurrent avec un nombre de places limité et un prix à la séance, partagez la séance comme routine de club et laissez les participants l\'enregistrer dans leur historique.',
	sections: [
		{
			heading: 'Avant de commencer',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Les cours payants ne sont pas encore actifs. Encaisser de l\'argent exige votre propre compte Stripe connecté ([[guide:get-paid-with-stripe|Être payé pour les événements que vous organisez]]) et l\'activation des paiements par la plateforme. D\'ici là, l\'interrupteur **Faire payer cet événement** reste désactivé et vous pouvez quand même proposer le cours gratuitement.',
				},
				{
					type: 'p',
					text: 'Vous devez être admin ou organisateur d\'événements du club. Le prix, la capacité et le calendrier de répétition se règlent sur le web ; l\'app mobile peut créer un cours mais n\'a pas de champs pour ces éléments.',
				},
			],
		},
		{
			heading: 'Créer le cours',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez votre club, allez dans l\'onglet **Événements** et appuyez sur **Nouvel événement**.',
						'Sous **Type d\'événement**, choisissez **Cours**. L\'itinéraire, la distance, l\'allure et les résultats de course sont masqués pour un cours.',
						'Renseignez la **Discipline**, par exemple « HIIT » ou « Bootcamp », et un **Titre** que les gens reconnaîtront dans le calendrier.',
						'Réglez la **Durée par défaut de la séance** sur la durée du cours en minutes. C\'est ce qui permet ensuite aux participants d\'enregistrer le cours en un seul geste.',
						'Indiquez la **Date**, l\'**Heure de départ**, la **Durée** et le **Point de rendez-vous**.',
						'Sous **Répétition**, choisissez **Hebdomadaire**, **Toutes les 2 semaines** ou **Mensuel** et les jours. Ce choix n\'est possible qu\'à la création de l\'événement.',
						'Réglez la **Capacité** sur votre nombre de racks, de vélos ou de places.',
						'Activez **Faire payer cet événement**, puis indiquez le **Prix**, la **Devise**, **Clôturer les ventes (minutes avant le début)** et une **Politique de remboursement**. Le prix et la devise ne peuvent plus être modifiés après la création de l\'événement.',
						'Appuyez sur **Créer l\'événement**.',
					],
				},
			],
		},
		{
			heading: 'Partager la séance avec votre cours',
			blocks: [
				{
					type: 'p',
					text: 'Un cours ne peut pas encore être associé directement à une routine de muscu. Publiez plutôt votre routine dans le club, où les membres peuvent la copier dans leurs propres routines et la suivre.',
				},
				{
					type: 'steps',
					items: [
						'Créez la routine : voir [[guide:build-a-gym-routine|Créer une routine de muscu]].',
						'Ouvrez la routine, puis sous **Publier dans un club**, choisissez votre club dans **Choisir un club…** et appuyez sur **Publier**.',
						'Elle apparaît dans l\'onglet **Modèles** du club sous **Modèles de routine de gym**, avec la mention **Modèle du club**. Les membres appuient sur **Adopter** pour obtenir leur propre copie.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Les admins du club peuvent aussi aller directement dans l\'onglet **Modèles**, appuyer sur **Ajouter un modèle** et choisir **Routine de gym**. Elle est enregistrée comme modèle de club en une seule étape.',
				},
			],
		},
		{
			heading: 'Les participants enregistrent le cours dans leur historique',
			blocks: [
				{
					type: 'p',
					text: 'Sur la page du cours, tout participant connecté voit **Enregistrer comme séance**. Cela ouvre une séance de muscu déjà nommée d\'après le cours, qu\'il peut ajuster avec ses propres séries et charges avant d\'enregistrer. Il voit ensuite **Ajouté à votre journal de muscu**, et le cours compte dans son historique d\'entraînement comme n\'importe quelle autre séance. Cela fonctionne sur le web et dans l\'app mobile.',
				},
				{
					type: 'p',
					text: 'Une personne qui a adopté votre routine peut plutôt l\'ouvrir et appuyer sur **Démarrer la routine** pour être guidée série par série ; cette séance est elle aussi enregistrée dans son journal de muscu.',
				},
			],
		},
		{
			heading: 'Inscriptions, jour J et modifications',
			blocks: [
				{
					type: 'list',
					items: [
						'Les participants s\'inscrivent et paient sur le web, voient **Vous êtes inscrit** et peuvent annuler selon votre [[guide:refund-policies|politique de remboursement]].',
						'Quand toutes les places sont prises, le cours affiche **Complet** et propose **Rejoindre la liste d’attente** : voir [[guide:waitlist-and-claim-window|Listes d\'attente et délai de 12 heures pour réclamer une place]].',
						'Notez qui est venu : [[guide:take-attendance|Faire l\'appel]].',
						'Annuler une séance rembourse tous ceux qui ont payé : [[guide:cancel-a-class|Annuler un cours]].',
					],
				},
			],
		},
	],
	sources: {
		title: '821d1cdaad9c7f76',
		summary: 'fe033ea704336c87',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '201303c3b4fb7856',
		's0.b1': 'cda7868c50d0cb5f',
		's1.heading': '2be2beb0fdaf15d0',
		's1.b0.i0': '7305ee21de6e7b5b',
		's1.b0.i1': '3c9d0e87dfbeb2b0',
		's1.b0.i2': 'f5ba5f09a6974c79',
		's1.b0.i3': '33a8a722caa47142',
		's1.b0.i4': '102511520e8a1371',
		's1.b0.i5': 'efd088144f85d66a',
		's1.b0.i6': 'd8ec205082050572',
		's1.b0.i7': '5a77ffc2b4ed6f03',
		's1.b0.i8': '854dff74efad02f9',
		's2.heading': 'bbcfb1ff6677d7c4',
		's2.b0': 'e950a3414f06b735',
		's2.b1.i0': 'dfaa37a59a8694bd',
		's2.b1.i1': 'e4888330a1cf50da',
		's2.b1.i2': '8583726358642cc9',
		's2.b2': '2399946b61bf3531',
		's3.heading': 'bde153fbfeb20de5',
		's3.b0': '073d6ee2cb1c9925',
		's3.b1': 'd33452cd85ac8ba2',
		's4.heading': '2f15ae20fe8166de',
		's4.b0.i0': '08b55370b0377e69',
		's4.b0.i1': 'd916d4671efc3512',
		's4.b0.i2': '53cda3f1ada8ad06',
		's4.b0.i3': 'd8fbf8a81896cecd',
	},
};
