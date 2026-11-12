import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'log-a-meal-from-a-photo',
	title: 'Registrar uma refeição a partir de uma foto',
	summary: 'Fotografe seu prato, deixe o Threkir estimar o que tem nele e confira e edite cada item antes que ele entre no seu registro alimentar.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'list',
					items: [
						'Registrar a partir de uma foto faz parte do Pro. Registrar alimentos manualmente continua gratuito.',
						'Ele usa IA, então precisa do aviso de IA mais recente. Se pedirem que você o aceite, abra Configurações → Conta e aceite lá.',
						'A foto só é usada para estimar o que está no prato. Os dados de localização e da câmera são removidos antes do envio, e o Threkir não guarda a foto.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ele talvez ainda não esteja ativado. Se você não vir **Registrar a partir de uma foto**, ele não está disponível para você.',
				},
			],
		},
		{
			heading: 'Na web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra [[route:/nutrition|Nutrição]] e selecione **Registrar comida** e depois **Registrar a partir de uma foto**.',
						'Selecione **Escolher uma foto** e escolha uma imagem da sua refeição.',
						'Adicione uma **Observação (opcional)** se ajudar, por exemplo meia porção.',
						'Selecione **Estimar**.',
					],
				},
			],
		},
		{
			heading: 'No app para celular',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra **Fitness**, escolha a aba **Nutrição** e toque no botão da câmera, **Registrar a partir de uma foto**.',
						'Toque em **Tirar foto** ou **Escolher foto**.',
						'Adicione uma **Observação (opcional)** se ajudar e toque em **Estimar**.',
					],
				},
			],
		},
		{
			heading: 'Conferir antes de salvar',
			blocks: [
				{
					type: 'p',
					text: 'Em **Confira antes de salvar**, cada alimento aparece com calorias, proteínas, carboidratos e gorduras. São estimativas, então confira.',
				},
				{
					type: 'list',
					items: [
						'Mude qualquer nome ou número que pareça errado. Os itens marcados com **Estimativa incerta** são os que mais merecem uma segunda olhada.',
						'Remova tudo o que não estiver no seu prato.',
						'Escolha a **Refeição** a que o alimento pertence.',
						'Selecione **Salvar itens** para adicionar o que sobrou ao seu registro alimentar. Nada é salvo antes disso.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se nenhum alimento for reconhecido, ou se você registrou muitas fotos na última hora, adicione a refeição manualmente como de costume.',
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
		's1.b0.i0': '01eae5b5a4e98d0f',
		's1.b0.i1': '29b05255de9bf718',
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
