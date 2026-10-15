import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'log-a-meal-from-a-photo',
	title: 'Saisir un repas depuis une photo',
	summary: 'Photographiez votre assiette, laissez Threkir estimer ce qu\'elle contient, puis vérifiez et modifiez chaque élément avant qu\'il n\'entre dans votre journal alimentaire.',
	sections: [
		{
			heading: 'Avant de commencer',
			blocks: [
				{
					type: 'list',
					items: [
						'La saisie depuis une photo fait partie de Pro. Saisir ses aliments à la main reste gratuit.',
						'Elle utilise l\'IA et nécessite donc la dernière version de l\'avis sur l\'IA. Si on vous demande de l\'accepter, ouvrez Réglages → Compte et acceptez-la là.',
						'La photo sert uniquement à estimer ce qu\'il y a dans l\'assiette. Les données de lieu et d\'appareil sont retirées avant l\'envoi, et Threkir ne conserve pas la photo.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Elle n\'est peut-être pas encore activée. Si vous ne voyez pas **Saisir depuis une photo**, elle n\'est pas disponible pour vous.',
				},
			],
		},
		{
			heading: 'Sur le web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez la page [[route:/nutrition/log|Enregistrer un aliment]].',
						'Sous **Saisir depuis une photo**, sélectionnez **Choisir une photo** et choisissez une image de votre repas.',
						'Ajoutez une **Note (facultatif)** si c\'est utile, par exemple demi-portion.',
						'Sélectionnez **Estimer**.',
					],
				},
			],
		},
		{
			heading: 'Dans l\'app mobile',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ouvrez **Fitness**, choisissez l\'onglet **Nutrition** et touchez le bouton appareil photo, **Saisir depuis une photo**.',
						'Touchez **Prendre une photo** ou **Choisir une photo**.',
						'Ajoutez une **Note (facultatif)** si c\'est utile, puis touchez **Estimer**.',
					],
				},
			],
		},
		{
			heading: 'Vérifier avant d\'enregistrer',
			blocks: [
				{
					type: 'p',
					text: 'Sous **Vérifiez avant d\'enregistrer**, chaque aliment apparaît avec ses calories, protéines, glucides et lipides. Ce sont des estimations : vérifiez-les.',
				},
				{
					type: 'list',
					items: [
						'Corrigez tout nom ou chiffre qui semble faux. Les éléments marqués **Estimation incertaine** sont ceux qui méritent le plus d\'être revus.',
						'Supprimez tout ce qui n\'est pas dans votre assiette.',
						'Choisissez le **Repas** auquel appartient l\'aliment.',
						'Sélectionnez **Enregistrer les entrées** pour ajouter ce qui reste à votre journal alimentaire. Rien n\'est enregistré avant.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si aucun aliment n\'est reconnu, ou si vous avez saisi beaucoup de photos dans la dernière heure, ajoutez le repas à la main comme d\'habitude.',
				},
			],
		},
	],
	sources: {
		title: 'bbdc9660a287e7c1',
		summary: 'aeef5fef4857acdc',
		's0.heading': '74e492d5d0df0bab',
		's0.b0.i0': 'd03e553125a96101',
		's0.b0.i1': 'ad91a1f646fd4777',
		's0.b0.i2': '63338ba4abc28ffc',
		's0.b1': '6791908473990cc8',
		's1.heading': '1e1b85a2667ca4d5',
		's1.b0.i0': '95844e8f3912970e',
		's1.b0.i1': '74bd9cd2cdc290a4',
		's1.b0.i2': 'e1f5d3b8c8fe13e4',
		's1.b0.i3': '945cfae0c52315dc',
		's2.heading': 'f21eaef94c685b5c',
		's2.b0.i0': 'c010f5524e29e935',
		's2.b0.i1': '788614966879c6fe',
		's2.b0.i2': 'c74ad67ce20e5723',
		's3.heading': 'a87450ed45241ef4',
		's3.b0': 'a770f2d0fc04e051',
		's3.b1.i0': 'ed3985f616eca37f',
		's3.b1.i1': '88c6d0416eae03ab',
		's3.b1.i2': 'ffc4a5ff20130b13',
		's3.b1.i3': '8f4ca5857c9f1f76',
		's3.b2': '8fea5a4dccf15c27',
	},
};
