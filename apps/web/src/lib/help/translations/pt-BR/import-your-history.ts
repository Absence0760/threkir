import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'import-your-history',
	title: 'Importar seu histórico de corridas',
	summary: 'Traga suas corridas anteriores do Strava, de uma exportação da Garmin ou do app de saúde do celular, e saiba o que acontece com arquivos GPX.',
	sections: [
		{
			heading: 'Conectar o Strava para corridas recentes e novas',
			blocks: [
				{
					type: 'steps',
					items: [
						'Na web, abra [[route:/settings/integrations|Integrações]] em Configurações e selecione **Conectar** no cartão do Strava; no app do celular, abra **Integrações** na aba **Você** e toque em Strava.',
						'Entre no Strava e permita o acesso.',
						'Suas corridas, caminhadas e trilhas dos últimos 90 dias são copiadas, e as novas atividades do Strava chegam automaticamente.',
					],
				},
				{
					type: 'p',
					text: 'Selecione **Sincronizar agora** para buscar de novo. Na web, **Até quando sincronizar** alcança até um ano para trás.',
				},
			],
		},
		{
			heading: 'Trazer todo o seu arquivo do Strava',
			blocks: [
				{
					type: 'p',
					text: 'Conectar o Strava só alcança a atividade recente. Para anos de histórico, use uma exportação de dados do Strava.',
				},
				{
					type: 'steps',
					items: [
						'No Strava, vá em Configurações, Minha conta, e solicite o seu arquivo. O Strava envia por e-mail um link para um arquivo zip.',
						'Na web, abra [[route:/settings/integrations|Integrações]], encontre **Importação em lote de uma exportação do Strava** e selecione **Escolher zip de exportação do Strava**. No app do celular, abra **Conta** na aba **Você**, depois **Importar de outro app**, e toque em **Importar ZIP do Strava**.',
						'Espere a importação terminar. As corridas que você já tem, por exemplo pela conexão com o Strava, são ignoradas, então é seguro rodar de novo.',
					],
				},
			],
		},
		{
			heading: 'Garmin e arquivos FIT',
			blocks: [
				{
					type: 'p',
					text: 'Uma conexão automática com o Garmin Connect ainda não está disponível porque a Garmin precisa aprová-la. Até lá, você pode importar arquivos da Garmin na web.',
				},
				{
					type: 'steps',
					items: [
						'No Garmin Connect, exporte uma atividade com Exportar original, que gera um arquivo .fit, ou solicite a exportação completa dos seus dados no Gerenciamento de conta da Garmin.',
						'Na web, abra [[route:/settings/integrations|Integrações]], encontre **Importação em lote de uma exportação da Garmin** e selecione **Escolher exportação da Garmin**.',
						'Escolha o arquivo .fit ou o zip. As atividades que você já importou são ignoradas.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'No Android, treinos que o app da Garmin, Samsung ou Fitbit grava no Health Connect também podem entrar por **Importar de outro app**. No iPhone, o mesmo cartão lê o Apple Saúde.',
				},
			],
		},
		{
			heading: 'GPX e outros arquivos avulsos',
			blocks: [
				{
					type: 'p',
					text: 'Um arquivo GPX, KML, KMZ, GeoJSON ou TCX avulso é importado como uma rota que você pode seguir, não como uma corrida no seu histórico. Abra [[route:/routes|Rotas]] na web ou a lista de rotas no app e importe por lá.',
				},
				{
					type: 'p',
					text: 'Arquivos GPX e TCX dentro de um zip de exportação do Strava ou da Garmin são lidos como corridas, então as importações em lote acima são o caminho para adicionar um histórico de atividades em GPX.',
				},
			],
		},
		{
			heading: 'Se algo não for importado',
			blocks: [
				{
					type: 'p',
					text: 'Quando algumas atividades ficam de fora, a importação lista cada uma e o motivo, como uma conexão que caiu ou um arquivo que não pôde ser lido. Rode a importação de novo para tentar outra vez: o que já entrou é ignorado, então nada é duplicado.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'As corridas importadas seguem a privacidade padrão das suas corridas, então confira essa configuração antes de uma importação grande se você não quiser que anos de corridas apareçam publicamente de uma vez. Veja [[guide:your-data-and-privacy|Seus dados e sua privacidade]].',
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
