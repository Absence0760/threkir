import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'import-your-history',
	title: 'Importar o seu histórico de corridas',
	summary: 'Traga as suas corridas antigas do Strava, de uma exportação da Garmin ou da app de saúde do telemóvel, e saiba o que acontece aos ficheiros GPX.',
	sections: [
		{
			heading: 'Ligar o Strava para corridas recentes e novas',
			blocks: [
				{
					type: 'steps',
					items: [
						'Na web, abra [[route:/settings/integrations|Integrações]] nas Definições e selecione **Ligar** no cartão do Strava; na app do telemóvel, abra **Integrações** no separador **Tu** e toque em Strava.',
						'Inicie sessão no Strava e permita o acesso.',
						'As suas corridas, caminhadas e trails dos últimos 90 dias são copiados, e as novas atividades do Strava chegam automaticamente.',
					],
				},
				{
					type: 'p',
					text: 'Selecione **Sincronizar agora** para voltar a importar. Na web, **Até quando sincronizar** permite recuar até um ano.',
				},
			],
		},
		{
			heading: 'Trazer todo o seu histórico do Strava',
			blocks: [
				{
					type: 'p',
					text: 'Ligar o Strava só alcança a atividade recente. Para anos de histórico, use uma exportação de dados do Strava.',
				},
				{
					type: 'steps',
					items: [
						'No Strava, vá a “Definições”, “A minha conta” e peça a exportação dos seus dados. O Strava envia-lhe por e-mail um link para um ficheiro zip.',
						'Na web, abra [[route:/settings/integrations|Integrações]], encontre **Importação em lote de uma exportação do Strava** e selecione **Escolher zip de exportação do Strava**. Na app do telemóvel, abra **Conta** no separador **Tu**, depois **Importar de outro app**, e toque em **Importar ZIP do Strava**.',
						'Aguarde que a importação termine. As corridas que já tem, por exemplo da sua ligação ao Strava, são ignoradas, por isso pode repeti-la em segurança.',
					],
				},
			],
		},
		{
			heading: 'Garmin e ficheiros FIT',
			blocks: [
				{
					type: 'p',
					text: 'Ainda não existe uma ligação automática ao Garmin Connect, porque a Garmin tem de a aprovar. Até lá, pode importar ficheiros da Garmin na web.',
				},
				{
					type: 'steps',
					items: [
						'No Garmin Connect, exporte uma atividade com “Export Original”, que lhe dá um ficheiro .fit, ou peça a exportação completa dos seus dados em Garmin Account Management.',
						'Na web, abra [[route:/settings/integrations|Integrações]], encontre **Importação em lote de uma exportação da Garmin** e selecione **Escolher exportação da Garmin**.',
						'Escolha o ficheiro .fit ou o zip. As atividades que já importou são ignoradas.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'No Android, os treinos que a app da Garmin, da Samsung ou da Fitbit escreve no Health Connect também podem entrar através de **Importar de outro app**. Num iPhone, o mesmo cartão lê o Apple Saúde.',
				},
			],
		},
		{
			heading: 'GPX e outros ficheiros individuais',
			blocks: [
				{
					type: 'p',
					text: 'Um único ficheiro GPX, KML, KMZ, GeoJSON ou TCX é importado como uma rota que pode seguir, não como uma corrida no seu histórico. Abra [[route:/routes|Rotas]] na web ou a lista de rotas na app e importe-o aí.',
				},
				{
					type: 'p',
					text: 'Os ficheiros GPX e TCX dentro de um zip de exportação do Strava ou da Garmin são lidos como corridas, por isso as importações em lote acima são a forma de adicionar um histórico de atividades GPX.',
				},
			],
		},
		{
			heading: 'Se algo não for importado',
			blocks: [
				{
					type: 'p',
					text: 'Quando algumas atividades ficam de fora, a importação lista cada uma e o motivo, como uma ligação que caiu ou um ficheiro que não foi possível ler. Volte a executar a importação para as tentar de novo: tudo o que já entrou é ignorado, por isso nada fica duplicado.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'As corridas importadas seguem a privacidade predefinida das suas corridas, por isso verifique-a antes de uma importação grande se não quiser que anos de corridas apareçam publicamente de uma só vez. Consulte [[guide:your-data-and-privacy|Os seus dados e a sua privacidade]].',
				},
			],
		},
	],
	sources: {
		title: '078b29389d32808d',
		summary: '440ddd94eca0b542',
		's0.heading': '69858eb69781e59e',
		's0.b0.i0': '92767a2a2bf7c191',
		's0.b0.i1': '8c05e0ad16ddb8c2',
		's0.b0.i2': '828e8880f5239f1c',
		's0.b1': '4302ec5e7767e8ab',
		's1.heading': '8abf228027d2a4fd',
		's1.b0': 'cf7faaa4679e66f2',
		's1.b1.i0': '9e771e203c299ace',
		's1.b1.i1': 'a6d02ee139faa051',
		's1.b1.i2': '0212bc406356fd62',
		's2.heading': 'f3f586814898940a',
		's2.b0': '25c859eb00073fae',
		's2.b1.i0': 'f82bc798e8ec1b4e',
		's2.b1.i1': '21d706b389df8c6a',
		's2.b1.i2': '69a212e6bb305cfc',
		's2.b2': '7d501c5e8de3d96e',
		's3.heading': '8b42dffcf7f0d635',
		's3.b0': '0dba61c98d441dad',
		's3.b1': '5dbef244bd55926e',
		's4.heading': '35509c7701b9dabc',
		's4.b0': '26a0daac64b29af6',
		's4.b1': '69e6cfdbe0110cea',
	},
};
