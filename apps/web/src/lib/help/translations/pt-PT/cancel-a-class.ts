import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'cancel-a-class',
	title: 'Cancelar uma aula e reembolsar todos os que pagaram',
	summary: 'Cancele uma ocorrência de uma aula recorrente; todos os que pagaram são reembolsados na totalidade automaticamente, com nova tentativa a cada hora e a opção Reembolsar agora.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'As aulas pagas ainda não estão disponíveis: precisam da conta Stripe do organizador ligada e da inscrição paga ativada pela plataforma. Se os pagamentos não estiverem disponíveis quando tentar cancelar uma ocorrência com inscrições pagas, verá **Esta ocorrência tem inscrições pagas e os pagamentos não estão disponíveis neste momento, por isso ainda não pode ser cancelada. Nada foi alterado.** A aula mantém-se, para que ninguém fique com um pagamento feito por uma aula que não se vai realizar.',
				},
				{
					type: 'p',
					text: 'Cancelar cabe aos administradores e organizadores de eventos do clube, e faz-se na web. As aulas gratuitas cancelam-se da mesma forma, apenas sem reembolsos.',
				},
			],
		},
		{
			heading: 'Cancelar uma ocorrência',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra a aula na web. Se se repetir, use **Escolha uma ocorrência** para escolher a data que vai cancelar.',
						'Prima **Cancelar esta ocorrência**.',
						'A caixa de diálogo explica que só esta ocorrência é cancelada e que o resto da série não é afetado. Numa aula paga, acrescenta: **Todas as pessoas inscritas nesta ocorrência são reembolsadas na totalidade, seja qual for a política de reembolso.**',
						'Se quiser, adicione um **Motivo (opcional)** e prima de novo **Cancelar esta ocorrência** para confirmar, ou **Manter** para desistir.',
					],
				},
				{
					type: 'p',
					text: 'Quando termina, vê quantas pessoas estão a ser reembolsadas, por exemplo *Ocorrência cancelada. 8 pessoas inscritas estão a ser reembolsadas na totalidade.* Quem estava a meio do pagamento vê o seu lugar reservado libertado e não é cobrado. Ninguém da lista de espera passa para uma aula cancelada.',
				},
			],
		},
		{
			heading: 'O que é dito aos participantes',
			blocks: [
				{
					type: 'p',
					text: 'Todas as pessoas que confirmaram presença nessa ocorrência (confirmadas, talvez ou na lista de espera) são notificadas. Quem pagou recebe uma notificação como *Uma ocorrência de “Reformer de terça” foi cancelada — o seu pagamento está a ser reembolsado*, e a mesma mensagem é enviada por email ou notificação push a quem as recebe. Diz *está a ser* reembolsado porque o reembolso é iniciado nesse momento e pode demorar alguns dias a chegar ao banco da pessoa.',
				},
			],
		},
		{
			heading: 'Se um reembolso falhar',
			blocks: [
				{
					type: 'p',
					text: 'A ocorrência fica cancelada mesmo que o Stripe recuse um reembolso. Verá uma mensagem a indicar quantos reembolsos não puderam ser iniciados, e a página da aula passa a ter um cartão **Reembolsos de ocorrências canceladas** que lista, por cada data cancelada, quem ainda não foi reembolsado, que reembolsos estão em curso e os que o banco devolveu.',
				},
				{
					type: 'list',
					items: [
						'A app volta a tentar automaticamente, uma vez por hora, todos os reembolsos ainda em dívida numa aula cancelada.',
						'Não precisa de esperar: prima **Reembolsar agora** junto à ocorrência para tentar de novo de imediato. Nunca reembolsa ninguém duas vezes.',
						'Um reembolso que o banco devolve não pode ser repetido desta forma; o valor é devolvido à pessoa por outra via.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Não reembolse as pessoas manualmente a partir de um painel do Stripe. Um reembolso feito aí pode não reverter o valor que lhe foi pago nem a taxa da plataforma, e a app pode depois reembolsar o restante por cima. Use antes **Reembolsar agora**.',
				},
			],
		},
		{
			heading: 'Aulas únicas e séries completas',
			blocks: [
				{
					type: 'p',
					text: '**Cancelar esta ocorrência** só é oferecido numa aula recorrente. Não há um botão único para cancelar uma série inteira: cancele cada ocorrência futura que tenha inscrições.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: '**Eliminar evento** não é um cancelamento. Remove o evento e todas as suas ocorrências e não reembolsa ninguém que tenha pago. Não elimine uma aula paga que ainda tenha inscrições.',
				},
				{
					type: 'p',
					text: 'Mudou de ideias? **Restabelecer esta ocorrência** volta a pôr uma data cancelada no calendário, mas os reembolsos já feitos não são anulados, pelo que as pessoas terão de se inscrever novamente.',
				},
			],
		},
	],
	sources: {
		title: '539c07215344e21b',
		summary: '3cde6837a6c4e13c',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': 'ae0f2cd6ce9f9514',
		's0.b1': '62f19ee1e9fb34c3',
		's1.heading': 'f95356ca142cc32c',
		's1.b0.i0': '98e1807ee36d2ae0',
		's1.b0.i1': '63ef622195f62b11',
		's1.b0.i2': '876f86b1b4e1070e',
		's1.b0.i3': '4aa8c04940065d46',
		's1.b1': '0d59321bed0664c0',
		's2.heading': '3fb0e8cd8d1ab1a9',
		's2.b0': '7fa0c327762bc337',
		's3.heading': '9ea612affe97dc23',
		's3.b0': '734dd195583da93f',
		's3.b1.i0': 'a63f61852a0c3de7',
		's3.b1.i1': '7f81dbe53b5fa733',
		's3.b1.i2': '17e04336cbe74225',
		's3.b2': '28dcde6e29894cdf',
		's4.heading': '335c84d82f12cfd6',
		's4.b0': 'bf92582fcb35608a',
		's4.b1': 'ccac613bf1514e51',
		's4.b2': '79b6ac5d2f43064a',
	},
};
