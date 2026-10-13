import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'what-pro-includes',
	title: 'O que o Pro inclui',
	summary: 'Todas as telas do Threkir são gratuitas; o Pro aumenta o seu limite do Treinador IA e coloca alguns processamentos em segundo plano na frente da fila.',
	sections: [
		{
			heading: 'O que continua grátis',
			blocks: [
				{
					type: 'p',
					text: 'Nada no app fica bloqueado atrás do Pro. Contas gratuitas têm gravação ilimitada no celular e no relógio, rotas, planos de treino e os números por trás deles, clubes e eventos, o feed social, contatos de segurança, importações e backups.',
				},
			],
		},
		{
			heading: 'O que o Pro acrescenta',
			blocks: [
				{
					type: 'list',
					items: [
						'**Coach IA — 10/dia**: dez mensagens ao Treinador IA por dia em vez de duas. A contagem é zerada à meia-noite UTC.',
						'Respostas do Treinador IA mais longas e completas, que podem levar em conta mais das suas corridas.',
						'**Map-matching prioritário**: os seus trajetos de GPS são ajustados às vias antes dos das contas gratuitas, então ficam prontos mais cedo.',
						'**Exportações para a nuvem prioritárias**: até 8 exportações de pacotes GPX por hora em vez de 2.',
						'**Geração de rotas no servidor**: circuitos traçados na rede de ruas real quando você gera uma rota por distância. Contas gratuitas continuam tendo a geração de circuitos, calculada no navegador.',
						'Descrições de rota mais ricas: na página de uma rota, **Aprimorar com IA** transforma a descrição padrão em um parágrafo mais completo.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Alguns desses recursos dependem de serviços que talvez ainda não estejam ativados. O cartão do Pro em [[route:/settings/upgrade|Pro e apoio]] lista apenas o que funciona hoje; se ele disser **O Pro desbloqueia o Coach de IA — em breve.**, o Pro ainda não pode ser comprado.',
				},
			],
		},
		{
			heading: 'Como obter o Pro',
			blocks: [
				{
					type: 'p',
					text: 'O Pro é uma assinatura mensal ou anual; o cartão do Pro mostra os preços atuais. Onde você pode comprá-lo depende do seu dispositivo:',
				},
				{
					type: 'list',
					items: [
						'Em um iPhone, abra **Pro e suporte** na aba **Você** e assine pela App Store.',
						'Na web, abra [[route:/settings/upgrade|Pro e apoio]] em Configurações. Se aparecer **A assinatura pela web chega em breve.**, assine pelo app para iPhone.',
					],
				},
				{
					type: 'p',
					text: 'O Pro pertence à sua conta, não ao seu dispositivo, então uma assinatura comprada em um dispositivo funciona em todos onde você entrar.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Os preços são em dólares americanos, e a App Store cobra o preço definido para o seu país. Alguns países e formas de pagamento não podem ser atendidos pelo nosso processador de pagamentos.',
				},
			],
		},
		{
			heading: 'Gerenciar ou cancelar',
			blocks: [
				{
					type: 'list',
					items: [
						'Cancele ou mude o seu plano onde você o iniciou: na App Store, na Play Store ou no portal de cobrança da web. **Gerenciar assinatura** leva você até lá.',
						'Em um celular novo, toque em **Restaurar compras** em **Pro e suporte** para trazer uma assinatura existente.',
						'Prefere uma contribuição única? **Doar** fica na mesma página.',
					],
				},
			],
		},
	],
	sources: {
		title: '4267811678bae9e8',
		summary: '959c30d7818df50f',
		's0.heading': '1319c99f2d10de2f',
		's0.b0': '4512e0ee677c9a74',
		's1.heading': '28933395a25968d0',
		's1.b0.i0': '719256df99c524da',
		's1.b0.i1': '2cc8c412ba418164',
		's1.b0.i2': '3be7590bced0492d',
		's1.b0.i3': 'a120796543f347bd',
		's1.b0.i4': 'abbb1f922ffbfa10',
		's1.b0.i5': 'dd0fa90eed200d7c',
		's1.b1': '076479f3bd42d0b5',
		's2.heading': '912eb19f965419db',
		's2.b0': 'ee79a267ee574aa9',
		's2.b1.i0': 'd455f1337a2fbaed',
		's2.b1.i1': 'f74f301604c6ba73',
		's2.b2': 'fd72c472718d9474',
		's2.b3': '0e5dc12fffad6bf9',
		's3.heading': '797ca5cca61c8cd4',
		's3.b0.i0': 'bb4062dcb71c0913',
		's3.b0.i1': '736765a7a1193432',
		's3.b0.i2': '1d83469669e327f0',
	},
};
