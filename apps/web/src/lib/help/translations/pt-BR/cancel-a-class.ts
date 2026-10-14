import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'cancel-a-class',
	title: 'Cancelar uma aula e reembolsar todos que pagaram',
	summary: 'Cancele uma ocorrência de uma aula recorrente; todos que pagaram por ela recebem o reembolso integral automaticamente, com uma nova tentativa a cada hora e a opção Reembolsar agora como alternativa.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'As aulas pagas ainda não estão disponíveis: elas exigem que a conta Stripe do organizador esteja conectada e que o sistema de pagamentos da plataforma esteja ativado. Se os pagamentos não estiverem disponíveis quando você tentar cancelar uma ocorrência com inscrições pagas, você verá **Esta ocorrência tem inscrições pagas e os pagamentos não estão disponíveis no momento, então ela ainda não pode ser cancelada. Nada foi alterado.** A aula continua marcada, para que ninguém fique com um pagamento feito por uma aula que não vai acontecer.',
				},
				{
					type: 'p',
					text: 'O cancelamento é feito por administradores e organizadores de eventos do clube, e acontece na web. Aulas gratuitas são canceladas da mesma forma, só que sem reembolsos.',
				},
			],
		},
		{
			heading: 'Cancelar uma ocorrência',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra a aula na web. Se ela se repete, use **Escolha uma ocorrência** para selecionar a data que você vai cancelar.',
						'Clique em **Cancelar esta ocorrência**.',
						'A caixa de diálogo explica que apenas esta ocorrência é cancelada e que o resto da série não é afetado. Em uma aula paga, ela acrescenta: **Todas as pessoas inscritas nesta ocorrência recebem o reembolso integral, independentemente da política de reembolso.**',
						'Se quiser, adicione um **Motivo (opcional)** e clique em **Cancelar esta ocorrência** de novo para confirmar, ou em **Manter** para desistir.',
					],
				},
				{
					type: 'p',
					text: 'Ao terminar, você vê quantas pessoas estão sendo reembolsadas, por exemplo *Ocorrência cancelada. 8 pessoas inscritas estão recebendo o reembolso integral.* Quem estava no meio do pagamento tem a vaga reservada liberada e não é cobrado. Ninguém da lista de espera é transferido para uma aula cancelada.',
				},
			],
		},
		{
			heading: 'O que seus participantes recebem',
			blocks: [
				{
					type: 'p',
					text: 'Todos que confirmaram presença nessa ocorrência (confirmados, talvez ou na lista de espera) são notificados. Quem pagou recebe uma notificação como *Uma ocorrência de “Reformer de terça” foi cancelada — seu pagamento está sendo reembolsado*, e o mesmo texto é enviado por e-mail ou push para quem recebe esses avisos. Ela diz *está sendo* reembolsado porque o reembolso é iniciado naquele momento e pode levar alguns dias para chegar ao banco da pessoa.',
				},
			],
		},
		{
			heading: 'Se um reembolso falhar',
			blocks: [
				{
					type: 'p',
					text: 'A ocorrência continua cancelada mesmo que o Stripe recuse um reembolso. Você verá uma mensagem dizendo quantos reembolsos não puderam ser iniciados, e a página da aula passa a ter um cartão **Reembolsos de ocorrências canceladas** que lista, por data cancelada, quem ainda não foi reembolsado, quais reembolsos estão em andamento e quais o banco devolveu.',
				},
				{
					type: 'list',
					items: [
						'O app tenta de novo, automaticamente e uma vez por hora, todos os reembolsos ainda devidos em uma aula cancelada.',
						'Você não precisa esperar: clique em **Reembolsar agora** ao lado da ocorrência para tentar de novo na mesma hora. Ninguém é reembolsado duas vezes.',
						'Um reembolso devolvido pelo banco não pode ser tentado de novo dessa forma; o valor é devolvido à pessoa de outra maneira.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Não reembolse as pessoas manualmente pelo painel do Stripe. Um reembolso feito por lá pode deixar de estornar o seu repasse e a taxa da plataforma, e o app pode então reembolsar o restante por cima. Use **Reembolsar agora**.',
				},
			],
		},
		{
			heading: 'Aulas avulsas e séries inteiras',
			blocks: [
				{
					type: 'p',
					text: '**Cancelar esta ocorrência** só aparece em aulas recorrentes. Não existe um botão único para cancelar uma série inteira: cancele cada próxima ocorrência que tenha inscrições.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: '**Excluir evento** não é um cancelamento. Ele remove o evento e todas as suas ocorrências e não reembolsa ninguém que pagou. Não exclua uma aula paga que ainda tenha inscrições.',
				},
				{
					type: 'p',
					text: 'Mudou de ideia? **Restabelecer esta ocorrência** coloca uma data cancelada de volta no calendário, mas os reembolsos já feitos não são desfeitos, então as pessoas vão precisar se inscrever de novo.',
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
