import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'log-a-meal-from-a-photo',
	title: 'Registar uma refeição a partir de uma fotografia',
	summary: 'Fotografe o seu prato, deixe o Threkir estimar o que tem e verifique e edite cada item antes de entrar no seu registo alimentar.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'list',
					items: [
						'Registar a partir de uma fotografia faz parte do Pro. Registar alimentos à mão continua gratuito.',
						'Usa IA, por isso precisa do aviso de IA mais recente. Se lhe pedirem para o aceitar, abra o Coach e aceite-o aí.',
						'A fotografia só é usada para estimar o que está no prato. Os dados de localização e da câmara são removidos antes do envio, e o Threkir não guarda a fotografia.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Pode ainda não estar ativado. Se não vir **Registar a partir de uma fotografia**, não está disponível para si.',
				},
			],
		},
		{
			heading: 'Na web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra a página [[route:/nutrition/log|Registar comida]].',
						'Em **Registar a partir de uma fotografia**, selecione **Escolher uma fotografia** e escolha uma imagem da sua refeição.',
						'Acrescente uma **Nota (opcional)** se ajudar, por exemplo meia dose.',
						'Selecione **Estimar**.',
					],
				},
			],
		},
		{
			heading: 'Na app do telemóvel',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra **Fitness**, escolha o separador **Nutrição** e toque no botão da câmara, **Registar a partir de uma fotografia**.',
						'Toque em **Tirar fotografia** ou **Escolher fotografia**.',
						'Acrescente uma **Nota (opcional)** se ajudar e toque em **Estimar**.',
					],
				},
			],
		},
		{
			heading: 'Verificar antes de guardar',
			blocks: [
				{
					type: 'p',
					text: 'Em **Verifique antes de guardar**, cada alimento aparece com as calorias, proteínas, hidratos de carbono e gordura. São estimativas, por isso verifique-as.',
				},
				{
					type: 'list',
					items: [
						'Altere qualquer nome ou número que pareça errado. Os itens marcados com **Estimativa incerta** são os que mais merecem uma segunda olhadela.',
						'Remova tudo o que não estiver no seu prato.',
						'Escolha a **Refeição** a que o alimento pertence.',
						'Selecione **Guardar entradas** para adicionar o que restar ao seu registo alimentar. Nada é guardado antes disso.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se nenhum alimento for reconhecido, ou se tiver registado muitas fotografias na última hora, adicione a refeição à mão como habitualmente.',
				},
			],
		},
	],
	sources: {
		title: 'bbdc9660a287e7c1',
		summary: 'aeef5fef4857acdc',
		's0.heading': '74e492d5d0df0bab',
		's0.b0.i0': 'd03e553125a96101',
		's0.b0.i1': 'd8c1c7bda37cffa1',
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
