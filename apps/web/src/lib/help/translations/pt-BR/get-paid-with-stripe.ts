import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'get-paid-with-stripe',
	title: 'Receber pelos eventos que você organiza',
	summary: 'Conecte uma conta de repasses Stripe uma única vez para que as aulas e os eventos que você organiza possam receber pagamentos, com o dinheiro indo para você e não para o clube.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'A inscrição paga ainda não está no ar. Cobrar por um evento exige duas coisas: sua própria conta Stripe conectada aqui e a plataforma ativar o sistema de pagamentos dela. Enquanto as duas não forem verdadeiras, ninguém pode ser cobrado. Se, ao clicar em **Configurar pagamentos**, aparecer **Os pagamentos ainda não estão configurados nesta versão.**, é a segunda que ainda falta, e não há nada para você fazer por enquanto.',
				},
				{
					type: 'p',
					text: 'Os repasses pertencem a *você*, não a um clube. O dinheiro de um evento vai para a pessoa que o organiza, então um coorganizador que nunca organiza uma aula nunca vê dinheiro que não é dele, e você mantém seus ganhos se deixar de organizar para um clube. Uma única conta de repasses cobre todos os clubes para os quais você organiza e todos os tipos de evento, inclusive uma [[guide:set-up-a-race|prova]].',
				},
			],
		},
		{
			heading: 'Conectar sua conta de repasses',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra [[route:/settings/payouts|Configurações, Repasses]] na web.',
						'Clique em **Configurar pagamentos**. Você é levado ao Stripe para informar seus dados e a conta bancária em que quer receber.',
						'Conclua as etapas do Stripe. Quando você voltar, a página mostra a sua situação.',
						'Se aparecer **Cadastro incompleto — conclua para começar a cobrar** ou **Sua conta de pagamentos precisa de atenção antes de você poder receber**, clique em **Concluir a configuração de pagamentos** para voltar ao Stripe e continuar de onde parou.',
					],
				},
			],
		},
		{
			heading: 'O que a situação significa',
			blocks: [
				{
					type: 'list',
					items: [
						'**Pronto para receber pagamentos**: o Stripe ativou as cobranças na sua conta, e **Abrir o painel do Stripe** leva você à sua conta Stripe. É isso que “cobranças ativadas” significa, e é o único estado em que a opção **Cobrar por este evento** de um novo evento pode ser ativada.',
						'**Cadastro incompleto — conclua para começar a cobrar**: o Stripe ainda precisa de algo seu antes de aceitar uma cobrança.',
						'**Sua conta de pagamentos precisa de atenção antes de você poder receber**: o Stripe restringiu a conta, geralmente porque quer mais informações. **Concluir a configuração de pagamentos** leva você ao que ele está pedindo.',
					],
				},
				{
					type: 'p',
					text: 'Até você estar pronto para receber pagamentos, o formulário do evento mostra **Configure os pagamentos para cobrar por eventos.** com um link **Configurar pagamentos** de volta para esta página.',
				},
			],
		},
		{
			heading: 'Taxas e quem cuida do quê',
			blocks: [
				{
					type: 'p',
					text: 'A plataforma cobra uma pequena taxa de cada inscrição, mostrada como **Taxa da plataforma** nos seus ganhos. A plataforma é a vendedora responsável (merchant of record): a cobrança leva o nome dela no extrato do comprador, os reembolsos são feitos pela plataforma conforme a política de reembolso que você define em cada evento, e uma cobrança contestada é debitada da conta Stripe da plataforma, não da sua. Quando um pedido é reembolsado integralmente, a taxa da plataforma sobre ele também é devolvida.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Não reembolse um comprador manualmente no Stripe. Use os caminhos do próprio app ([[guide:refund-policies|o cancelamento de um comprador]] ou [[guide:cancel-a-class|o cancelamento de uma ocorrência]]), que revertem o seu repasse e a taxa da plataforma juntos e mantêm seus números de ganhos corretos.',
				},
			],
		},
		{
			heading: 'Ver quanto você ganhou',
			blocks: [
				{
					type: 'p',
					text: 'A seção **Ganhos** na mesma página mostra quanto você recebeu pelas suas aulas, com um bloco por mês e moeda. Uma aula é registrada no mês em que aconteceu, no fuso horário dela, e não no mês em que alguém pagou, então “minhas aulas de outubro” são as aulas que aconteceram em outubro.',
				},
				{
					type: 'list',
					items: [
						'**Inscrições**, **Bruto**, **Reembolsado** e **Taxa da plataforma** do mês, e **Líquido para você** no final.',
						'Um detalhamento por aula, com as colunas **Aula** e **Quando**.',
						'Um reembolso que o banco devolveu fica fora dos totais até ser resolvido, e a seção informa quantos existem.',
					],
				},
				{
					type: 'p',
					text: 'Antes de alguém pagar, aparece **Ainda não há inscrições pagas. Assim que alguém pagar uma das suas aulas, ela aparece aqui.** Por enquanto, os ganhos estão só na web.',
				},
			],
		},
	],
	sources: {
		title: 'f9207157d1280332',
		summary: '790080559509072a',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '94bdd45ffa45992b',
		's0.b1': 'a2c35333af5a1b69',
		's1.heading': '3f872765a64cbf87',
		's1.b0.i0': 'e50bbd6128265cce',
		's1.b0.i1': '0f46885c40eac7c9',
		's1.b0.i2': '5c865b5f5c133459',
		's1.b0.i3': '8dda9f151d4fc524',
		's2.heading': '1efee8cc7e563d7a',
		's2.b0.i0': '02332a68186a1ac7',
		's2.b0.i1': '7215a841b76d02d7',
		's2.b0.i2': '482a0774b06a0a05',
		's2.b1': '97218ad8cd1cbafc',
		's3.heading': 'dd310d8f72e99c50',
		's3.b0': '67194d07a6c76aca',
		's3.b1': 'b0ca08b2dbcff463',
		's4.heading': 'e819e6fcb745f74c',
		's4.b0': '158c0402a17ba033',
		's4.b1.i0': '1f9a53c012335688',
		's4.b1.i1': '69d92aabe5b8e3c6',
		's4.b1.i2': 'da7f4f45de54e110',
		's4.b2': 'e6e13ff04eb65dc4',
	},
};
