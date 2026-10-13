import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'what-pro-includes',
	title: 'O que o Pro inclui',
	summary: 'Todos os ecrãs do Threkir são gratuitos; o Pro aumenta o seu limite do Treinador IA e passa algum trabalho em segundo plano para a frente da fila.',
	sections: [
		{
			heading: 'O que continua gratuito',
			blocks: [
				{
					type: 'p',
					text: 'Nada na app está bloqueado pelo Pro. As contas gratuitas têm gravação ilimitada no telemóvel e no relógio, rotas, planos de treino e os números por trás deles, clubes e eventos, o feed social, contactos de segurança, importações e backups.',
				},
			],
		},
		{
			heading: 'O que o Pro acrescenta',
			blocks: [
				{
					type: 'list',
					items: [
						'**Coach IA — 10/dia**: dez mensagens do Treinador IA por dia em vez de duas. A contagem é reposta à meia-noite UTC.',
						'Respostas do Treinador mais longas e completas, que podem ter em conta mais das suas corridas.',
						'**Map-matching prioritário**: os seus trajetos GPS são ajustados às estradas antes dos das contas gratuitas, por isso ficam prontos mais cedo.',
						'**Exportações para a nuvem prioritárias**: até 8 exportações de pacotes GPX por hora em vez de 2.',
						'**Geração de rotas no servidor**: circuitos traçados na rede viária real quando gera uma rota por distância. As contas gratuitas continuam a ter geração de circuitos, calculada no navegador.',
						'Descrições de rotas mais ricas: na página de uma rota, **Melhorar com IA** transforma a descrição normal num parágrafo mais completo.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Algumas destas funcionalidades dependem de serviços que podem ainda não estar ativados. O cartão Pro em [[route:/settings/upgrade|Pro e apoio]] só lista o que funciona hoje; se disser **O Pro desbloqueia o Coach de IA — em breve.**, o Pro ainda não pode ser comprado.',
				},
			],
		},
		{
			heading: 'Como obter o Pro',
			blocks: [
				{
					type: 'p',
					text: 'O Pro é uma subscrição mensal ou anual; o cartão Pro mostra os preços atuais. Onde o pode comprar depende do seu dispositivo:',
				},
				{
					type: 'list',
					items: [
						'Num iPhone, abra **Pro e suporte** no separador **Tu** e subscreva através da App Store.',
						'Na web, abra [[route:/settings/upgrade|Pro e apoio]] nas Definições. Se disser **A subscrição pela web chega em breve.**, subscreva antes na app para iPhone.',
					],
				},
				{
					type: 'p',
					text: 'O Pro pertence à sua conta, não ao seu dispositivo, por isso uma subscrição comprada num dispositivo funciona em todos os dispositivos onde iniciar sessão.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Os preços estão em dólares americanos, e a App Store cobra o preço definido para o seu país. Alguns países e métodos de pagamento não podem ser servidos pelo nosso processador de pagamentos.',
				},
			],
		},
		{
			heading: 'Gerir ou cancelar',
			blocks: [
				{
					type: 'list',
					items: [
						'Cancele ou altere o seu plano onde o iniciou: na App Store, na Play Store ou no portal de faturação da web. **Gerir subscrição** leva-o até lá.',
						'Num telemóvel novo, toque em **Restaurar compras** em **Pro e suporte** para transferir uma subscrição existente.',
						'Prefere fazer uma contribuição única? **Doar** está na mesma página.',
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
