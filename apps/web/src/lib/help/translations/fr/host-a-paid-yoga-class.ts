import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'host-a-paid-yoga-class',
	title: 'Organiser un cours payant de yoga ou de pilates',
	summary: 'Planifiez un cours récurrent pour votre club, limitez le nombre de tapis, fixez un prix à la séance et une politique de remboursement, et joignez une séquence minutée à suivre.',
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
					type: 'list',
					items: [
						'Vous devez être admin ou organisateur d\'événements du club. La page du club vous indique lequel avec **Vous êtes admin** ou **Vous êtes organisateur d\'événements**.',
						'Le prix, la capacité, le calendrier de répétition et le plan de séance se règlent tous sur le web. L\'app mobile peut créer un cours et l\'affiche aux membres, mais elle n\'a pas de champs pour le prix, la capacité ou le plan de séance.',
						'Si vous voulez joindre une séquence, créez-la d\'abord : voir [[guide:build-a-session-plan|Créer un plan de séance]].',
					],
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
						'Sous **Type d\'événement**, choisissez **Cours**. L\'itinéraire, la distance, l\'allure et les résultats de course disparaissent, car un cours n\'en a pas besoin.',
						'Renseignez la **Discipline**, par exemple « Pilates reformer ». Elle indique le style dans la liste.',
						'Réglez si vous le souhaitez la **Durée par défaut de la séance** en minutes. Avec une discipline ou une durée renseignée, les participants voient un bouton **Enregistrer comme séance** sur la page du cours.',
						'Choisissez si vous le souhaitez un **Plan de séance** pour joindre votre séquence minutée. Laissé sur **Aucun**, le cours se déroule sans plan.',
						'Donnez-lui un **Titre**, puis la **Date**, l\'**Heure de départ**, la **Durée** et un **Point de rendez-vous** qu\'un inconnu pourrait trouver, comme l\'adresse du studio.',
					],
				},
			],
		},
		{
			heading: 'Calendrier, capacité et prix',
			blocks: [
				{
					type: 'steps',
					items: [
						'Sous **Répétition**, choisissez **Hebdomadaire**, **Toutes les 2 semaines** ou **Mensuel**, puis les jours et la fin de la série avec **Se termine le** ou **Se termine après**. Le calendrier ne peut être choisi qu\'à la création de l\'événement.',
						'Réglez la **Capacité** sur le nombre de tapis. Une fois ce nombre d\'inscrits atteint, la personne suivante rejoint une liste d\'attente.',
						'Activez **Faire payer cet événement** et saisissez le **Prix** et la **Devise**. Les deux sont figés une fois l\'événement créé : vérifiez-les maintenant.',
						'Réglez **Clôturer les ventes (minutes avant le début)**. Zéro laisse les inscriptions ouvertes jusqu\'au début.',
						'Choisissez une **Politique de remboursement** : **Remboursement intégral jusqu’à l’heure de début**, **Remboursement intégral jusqu’à 24 h avant** ou **Aucun remboursement**. Voir [[guide:refund-policies|Politiques de remboursement]].',
						'Appuyez sur **Créer l\'événement**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'L\'inscription payante est réservée aux cours en présentiel. Chaque occurrence d\'un cours récurrent se paie séparément, comme une séance à l\'unité.',
				},
			],
		},
		{
			heading: 'Ce que voient vos participants',
			blocks: [
				{
					type: 'list',
					items: [
						'La discipline, l\'heure, le lieu, le **Prix** et une ligne sur l\'annulation, comme **Annulation gratuite jusqu\'à 24 heures avant le début**.',
						'Un bouton *S’inscrire · 22,00 $US* (avec votre prix) qui les mène au paiement. À leur retour, il indique **Paiement confirmé — vous êtes inscrit.**',
						'**Complet** quand tous les tapis sont pris, avec **Rejoindre la liste d’attente** tant que les ventes sont ouvertes ([[guide:waitlist-and-claim-window|fonctionnement de la liste d\'attente]]), et **Inscriptions closes** une fois les ventes arrêtées.',
						'Votre séquence sous **Séquence de la séance**. Ils peuvent l\'ouvrir et appuyer sur **Démarrer la séance** pour la suivre chez eux.',
					],
				},
				{
					type: 'p',
					text: 'L\'inscription et le paiement se font sur le web. L\'app mobile affiche le cours mais n\'a pas encore de bouton d\'inscription.',
				},
			],
		},
		{
			heading: 'Le jour J et après',
			blocks: [
				{
					type: 'list',
					items: [
						'Notez qui est venu : [[guide:take-attendance|Faire l\'appel]].',
						'Besoin d\'annuler une séance ? [[guide:cancel-a-class|Annuler un cours]] rembourse tous ceux qui ont payé.',
						'L\'argent arrive sur votre propre compte de paiement, moins les frais de plateforme, et apparaît sous **Revenus** dans [[route:/settings/payouts|Paiements]].',
					],
				},
				{
					type: 'p',
					text: 'Vous avez oublié le plan à la création ? Sur la page du cours, les organisateurs peuvent utiliser **Associer à un événement de cours** dans la carte **Séquence de la séance** pour en choisir un plus tard.',
				},
			],
		},
	],
	sources: {
		title: 'f9202893d367af51',
		summary: '03c1c7e17dcc968e',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '201303c3b4fb7856',
		's0.b1.i0': '2d587baadbd80587',
		's0.b1.i1': '72edebed568a4cad',
		's0.b1.i2': 'f20607bacb45c7dd',
		's1.heading': '2be2beb0fdaf15d0',
		's1.b0.i0': '7305ee21de6e7b5b',
		's1.b0.i1': 'df3070e1c4eff364',
		's1.b0.i2': 'a0043c7cfd2bbc7e',
		's1.b0.i3': '8be48d85d67ddf24',
		's1.b0.i4': 'a2a8189648081381',
		's1.b0.i5': '52dea2ca1d1472d1',
		's2.heading': 'ce77363846b787e4',
		's2.b0.i0': 'a0c8dc4b3ac13dbd',
		's2.b0.i1': '0609f9b1dd9c4465',
		's2.b0.i2': 'ac80424ab23fc1e5',
		's2.b0.i3': '56cd20b7328af3b4',
		's2.b0.i4': 'e8c24babc3d8d306',
		's2.b0.i5': '854dff74efad02f9',
		's2.b1': '69317be4e4a0756e',
		's3.heading': '0f1e266ce779db54',
		's3.b0.i0': '52728d1f26fab9d8',
		's3.b0.i1': '5e258c088e1b7e0d',
		's3.b0.i2': '2144a950995dac3b',
		's3.b0.i3': 'ec364e50f1fad47b',
		's3.b1': 'ffc81c0539754c16',
		's4.heading': '4002e4389f6911d1',
		's4.b0.i0': 'fe0269bf50bde50e',
		's4.b0.i1': '44146e54a72db714',
		's4.b0.i2': '16ab6ec3268cd0ba',
		's4.b1': '0393c21d3c3510d3',
	},
};
