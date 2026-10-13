import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'host-a-paid-yoga-class',
	title: 'Organizar uma aula paga de ioga ou pilates',
	summary: 'Agende uma aula recorrente para o seu clube, limite os tapetes, defina um preço por aula e uma política de reembolso e associe uma sequência cronometrada que as pessoas podem seguir.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'As aulas pagas ainda não estão disponíveis. Receber dinheiro exige a sua própria conta Stripe ligada ([[guide:get-paid-with-stripe|Receber pagamento pelos eventos que organiza]]) e a inscrição paga ativada pela plataforma. Até lá, o interruptor **Cobrar por este evento** fica desligado e pode continuar a dar a aula gratuitamente.',
				},
				{
					type: 'list',
					items: [
						'Tem de ser administrador ou organizador de eventos do clube. A página do clube indica qual dos dois é com **É administrador** ou **É organizador de eventos**.',
						'O preço, a capacidade, o calendário de repetição e o plano de sessão definem-se todos na web. A app do telemóvel pode criar uma aula e mostra-a aos membros, mas não tem campos de preço, capacidade nem plano de sessão.',
						'Se quiser associar uma sequência, crie-a primeiro: consulte [[guide:build-a-session-plan|Criar um plano de sessão]].',
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
						'Abra o seu clube, vá ao separador **Eventos** e prima **Novo evento**.',
						'Em **Tipo de evento**, escolha **Aula**. O percurso, a distância, o ritmo e os resultados de prova desaparecem, porque uma aula não precisa deles.',
						'Preencha a **Disciplina**, por exemplo “Pilates reformer”. É o nome do estilo na listagem.',
						'Se quiser, defina a **Duração predefinida do treino** em minutos. Com uma disciplina ou uma duração definida, os participantes têm um botão **Registar como treino** na página da aula.',
						'Se quiser, escolha um **Plano de sessão** para associar a sua sequência cronometrada. Se ficar em **Nenhum**, a aula decorre sem plano.',
						'Dê-lhe um **Título** e depois a **Data**, a **Hora de início**, a **Duração** e um **Ponto de encontro** que um desconhecido consiga encontrar, como a morada do estúdio.',
					],
				},
			],
		},
		{
			heading: 'Calendário, capacidade e preço',
			blocks: [
				{
					type: 'steps',
					items: [
						'Em **Repetição**, escolha **Semanal**, **A cada 2 semanas** ou **Mensal**, depois os dias e quando a série termina, com **Termina em** ou **Termina após**. O calendário só pode ser escolhido enquanto está a criar o evento.',
						'Defina a **Capacidade** com o número de tapetes. Quando estiver inscrito esse número de pessoas, a pessoa seguinte entra numa lista de espera.',
						'Ative **Cobrar por este evento** e introduza o **Preço** e a **Moeda**. Ambos ficam fixos depois de o evento ser criado, por isso confirme-os agora.',
						'Defina **Encerrar vendas (minutos antes do início)**. Com zero, a inscrição fica aberta até ao início.',
						'Escolha uma **Política de reembolso**: **Reembolso total até à hora de início**, **Reembolso total até 24h antes** ou **Sem reembolsos**. Consulte [[guide:refund-policies|Políticas de reembolso]].',
						'Prima **Criar evento**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'A inscrição paga é apenas para aulas presenciais. Cada ocorrência de uma aula recorrente é paga em separado, como uma aula avulsa.',
				},
			],
		},
		{
			heading: 'O que os participantes veem',
			blocks: [
				{
					type: 'list',
					items: [
						'A disciplina, a hora, o local, o **Preço** e uma linha sobre o cancelamento, como **Cancelamento gratuito até 24 horas antes do início**.',
						'Um botão com *Inscrever-se · 22,00 US$* (com o seu preço) que os leva ao pagamento. Quando voltam, aparece **Pagamento confirmado — está inscrito.**',
						'**Esgotado** quando os tapetes estão todos ocupados, com **Entrar na lista de espera** enquanto as vendas estão abertas ([[guide:waitlist-and-claim-window|como funciona a lista de espera]]), e **Inscrições encerradas** quando as vendas terminam.',
						'A sua sequência em **Sequência da sessão**. Podem abri-la e premir **Iniciar sessão** para a seguir em casa.',
					],
				},
				{
					type: 'p',
					text: 'A inscrição e o pagamento fazem-se na web. A app do telemóvel mostra a aula, mas ainda não tem botão de inscrição.',
				},
			],
		},
		{
			heading: 'No dia e depois',
			blocks: [
				{
					type: 'list',
					items: [
						'Marque quem veio: [[guide:take-attendance|Registar presenças]].',
						'Precisa de cancelar uma? [[guide:cancel-a-class|Cancelar uma aula]] reembolsa todos os que pagaram.',
						'O dinheiro vai para a sua própria conta de pagamentos, descontada a taxa da plataforma, e aparece em **Receitas** em [[route:/settings/payouts|Pagamentos]].',
					],
				},
				{
					type: 'p',
					text: 'Esqueceu-se do plano ao criar a aula? Na página da aula, os organizadores podem usar **Vincular a um evento de aula** no cartão **Sequência da sessão** para escolher um mais tarde.',
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
