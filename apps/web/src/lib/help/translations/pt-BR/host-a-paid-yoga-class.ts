import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'host-a-paid-yoga-class',
	title: 'Oferecer uma aula paga de ioga ou pilates',
	summary: 'Agende uma aula recorrente para o seu clube, limite o número de tapetes, defina um preço avulso e uma política de reembolso e vincule uma sequência cronometrada que as pessoas possam acompanhar.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'As aulas pagas ainda não estão disponíveis. Receber pagamentos exige a sua própria conta Stripe conectada ([[guide:get-paid-with-stripe|Receber pelos eventos que você organiza]]) e o sistema de pagamentos da plataforma ativado. Até lá, a opção **Cobrar por este evento** fica desligada e você ainda pode dar a aula de graça.',
				},
				{
					type: 'list',
					items: [
						'Você precisa ser administrador ou organizador de eventos do clube. A página do clube mostra qual dos dois com **Você é administrador** ou **Você é organizador de eventos**.',
						'Preço, capacidade, a programação de repetição e o plano de sessão são todos definidos na web. O app para celular pode criar uma aula e mostrá-la aos membros, mas não tem campos de preço, capacidade nem plano de sessão.',
						'Se quiser vincular uma sequência, monte-a primeiro: veja [[guide:build-a-session-plan|Montar um plano de sessão]].',
					],
				},
			],
		},
		{
			heading: 'Criar a aula',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o seu clube, vá até a aba **Eventos** e clique em **Novo evento**.',
						'Em **Tipo de evento**, escolha **Aula**. Rota, distância, ritmo e resultados de prova desaparecem, porque uma aula não precisa deles.',
						'Preencha a **Modalidade**, por exemplo “Pilates reformer”. Ela indica o estilo na listagem.',
						'Se quiser, defina a **Duração padrão do treino** em minutos. Com uma disciplina ou uma duração definida, os participantes ganham um botão **Registrar como treino** na página da aula.',
						'Se quiser, escolha um **Plano de sessão** para vincular a sua sequência cronometrada. Deixando em **Nenhum**, a aula acontece sem sequência.',
						'Dê a ela um **Título** e depois a **Data**, o **Horário de início**, a **Duração** e um **Ponto de encontro** que um desconhecido consiga encontrar, como o endereço do estúdio.',
					],
				},
			],
		},
		{
			heading: 'Programação, capacidade e preço',
			blocks: [
				{
					type: 'steps',
					items: [
						'Em **Repetição**, escolha **Semanal**, **A cada 2 semanas** ou **Mensal**, depois os dias e quando a série termina, com **Termina em** ou **Termina após**. A programação só pode ser escolhida enquanto você cria o evento.',
						'Defina a **Capacidade** como o número de tapetes. Quando esse número de pessoas estiver inscrito, a próxima pessoa entra em uma lista de espera.',
						'Ative **Cobrar por este evento** e informe o **Preço** e a **Moeda**. Os dois ficam fixos depois que o evento é criado, então confira agora.',
						'Defina **Encerrar vendas (minutos antes do início)**. Zero mantém as inscrições abertas até a hora do início.',
						'Escolha uma **Política de reembolso**: **Reembolso total até o horário de início**, **Reembolso total até 24h antes** ou **Sem reembolsos**. Veja [[guide:refund-policies|Políticas de reembolso]].',
						'Clique em **Criar evento**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'A inscrição paga é só para aulas presenciais. Cada ocorrência de uma aula recorrente é paga separadamente, como uma aula avulsa.',
				},
			],
		},
		{
			heading: 'O que seus participantes veem',
			blocks: [
				{
					type: 'list',
					items: [
						'A disciplina, o horário, o local, o **Preço** e uma linha sobre cancelamento, como **Cancelamento gratuito até 24 horas antes do início**.',
						'Um botão com o texto *Inscrever-se · US$ 22* (com o seu preço) que leva ao pagamento. Quando a pessoa volta, ele mostra **Pagamento confirmado — você está inscrito.**',
						'**Esgotado** quando os tapetes acabam, com **Entrar na lista de espera** enquanto as vendas estão abertas ([[guide:waitlist-and-claim-window|como funciona a lista de espera]]), e **Inscrições encerradas** quando as vendas terminam.',
						'A sua sequência em **Sequência da sessão**. A pessoa pode abri-la e clicar em **Iniciar sessão** para acompanhar em casa.',
					],
				},
				{
					type: 'p',
					text: 'A inscrição e o pagamento acontecem na web. O app para celular mostra a aula, mas ainda não tem botão de inscrição.',
				},
			],
		},
		{
			heading: 'No dia e depois',
			blocks: [
				{
					type: 'list',
					items: [
						'Marque quem compareceu: [[guide:take-attendance|Registrar a presença]].',
						'Precisa cancelar uma? [[guide:cancel-a-class|Cancelar uma aula]] reembolsa todos que pagaram.',
						'O dinheiro vai para a sua própria conta de repasses, descontada a taxa da plataforma, e aparece em **Ganhos** em [[route:/settings/payouts|Repasses]].',
					],
				},
				{
					type: 'p',
					text: 'Esqueceu o plano na criação? Na página da aula, os organizadores podem usar **Vincular a um evento de aula** no cartão **Sequência da sessão** para escolher um depois.',
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
