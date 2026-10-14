import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'get-paid-with-stripe',
	title: 'Receber pagamento pelos eventos que organiza',
	summary: 'Ligue uma conta de pagamentos Stripe uma única vez para que as aulas e eventos que organiza possam cobrar, com o dinheiro a ir para si e não para o clube.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'A inscrição paga ainda não está disponível. Cobrar por um evento exige duas coisas: a sua própria conta Stripe ligada aqui e a plataforma ativar a inscrição paga. Enquanto não se verificarem ambas, ninguém pode ser cobrado. Se, ao premir **Configurar pagamentos**, aparecer **Os pagamentos ainda não estão configurados nesta versão.**, é a segunda que ainda falta e, por agora, não há nada que tenha de fazer.',
				},
				{
					type: 'p',
					text: 'Os pagamentos pertencem a *si*, não a um clube. O dinheiro de um evento vai para a pessoa que o organiza, por isso quem coorganiza um clube mas nunca organiza uma aula nunca vê dinheiro que não lhe pertence, e mantém as suas receitas se deixar de organizar para um clube. Uma só conta de pagamentos cobre todos os clubes para os quais organiza e todos os tipos de evento, incluindo uma [[guide:set-up-a-race|prova]].',
				},
			],
		},
		{
			heading: 'Ligar a sua conta de pagamentos',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra [[route:/settings/payouts|Definições, Pagamentos]] na web.',
						'Prima **Configurar pagamentos**. É encaminhado para o Stripe para introduzir os seus dados e a conta bancária onde quer receber.',
						'Conclua os passos do Stripe. Quando voltar, a página mostra o seu estado.',
						'Se indicar **Registo incompleto — conclua para começar a cobrar** ou **A sua conta de pagamentos precisa de atenção antes de poder receber**, prima **Concluir a configuração de pagamentos** para voltar ao Stripe e continuar onde ficou.',
					],
				},
			],
		},
		{
			heading: 'O que significa o estado',
			blocks: [
				{
					type: 'list',
					items: [
						'**Pronto para receber pagamentos**: o Stripe ativou as cobranças na sua conta, e **Abrir o painel do Stripe** leva-o à sua conta Stripe. É isto que significa “cobranças ativadas”, e é o único estado em que o interruptor **Cobrar por este evento** de um novo evento pode ser ativado.',
						'**Registo incompleto — conclua para começar a cobrar**: o Stripe ainda precisa de algo da sua parte antes de aceitar uma cobrança.',
						'**A sua conta de pagamentos precisa de atenção antes de poder receber**: o Stripe restringiu a conta, normalmente porque quer mais informações. **Concluir a configuração de pagamentos** leva-o ao que está a ser pedido.',
					],
				},
				{
					type: 'p',
					text: 'Enquanto não estiver pronto para receber pagamentos, o formulário do evento mostra **Configure os pagamentos para cobrar por eventos.** com uma ligação **Configurar pagamentos** de volta a esta página.',
				},
			],
		},
		{
			heading: 'Taxas e quem trata de quê',
			blocks: [
				{
					type: 'p',
					text: 'A plataforma cobra uma pequena taxa por cada inscrição, apresentada como **Taxa da plataforma** nas suas receitas. A plataforma é o comerciante responsável: a cobrança aparece com o nome dela no extrato de quem compra, os reembolsos são emitidos pela plataforma de acordo com a política de reembolso que definir em cada evento, e uma cobrança contestada é debitada da conta Stripe da plataforma, não da sua. Quando um pedido é totalmente reembolsado, a taxa da plataforma sobre ele também é devolvida.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Não reembolse um comprador manualmente no Stripe. Use os caminhos da própria app ([[guide:refund-policies|o cancelamento por parte do comprador]] ou [[guide:cancel-a-class|o cancelamento de uma ocorrência]]), que revertem em conjunto o valor que lhe foi pago e a taxa da plataforma e mantêm corretos os valores das suas receitas.',
				},
			],
		},
		{
			heading: 'Ver o que recebeu',
			blocks: [
				{
					type: 'p',
					text: 'A secção **Receitas** na mesma página mostra o que recebeu pelas suas aulas, com um bloco por mês e por moeda. Uma aula é contabilizada no mês em que decorreu, no fuso horário da própria aula, e não no mês em que alguém pagou, por isso “as minhas aulas de outubro” são as aulas que aconteceram em outubro.',
				},
				{
					type: 'list',
					items: [
						'**Inscrições**, **Bruto**, **Reembolsado** e **Taxa da plataforma** do mês e, no fim, **Líquido para si**.',
						'Uma discriminação por aula, com as colunas **Aula** e **Quando**.',
						'Um reembolso que o banco devolveu fica fora dos totais até ser resolvido, e a secção indica quantos há.',
					],
				},
				{
					type: 'p',
					text: 'Antes de alguém pagar, aparece **Ainda não há inscrições pagas. Assim que alguém pagar uma das suas aulas, ela aparece aqui.** Por agora, as receitas só estão disponíveis na web.',
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
