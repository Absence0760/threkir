import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'waitlist-and-claim-window',
	title: 'Listas de espera e o prazo de 12 horas para garantir a vaga',
	summary: 'Como funciona entrar em uma aula lotada, como uma vaga liberada fica reservada para você por 12 horas em uma aula paga e o que acontece se você não a garantir.',
	sections: [
		{
			heading: 'Aulas gratuitas: você entra automaticamente',
			blocks: [
				{
					type: 'p',
					text: 'Quando uma aula gratuita com **Capacidade** está lotada, escolher **Eu vou** coloca você na lista de espera, e sua confirmação mostra **Na lista de espera**. Quando alguém desiste, a primeira pessoa da lista de espera passa automaticamente para **Confirmado**; não há nada a garantir. Isso funciona na web e no app do celular.',
				},
			],
		},
		{
			heading: 'Aulas pagas: uma vaga é reservada, depois você paga',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'As aulas pagas ainda não estão no ar: elas exigem a conta Stripe do organizador conectada e o sistema de pagamentos da plataforma ativado. Tudo nesta seção vale a partir do momento em que isso acontecer.',
				},
				{
					type: 'p',
					text: 'Ninguém é cobrado só por estar em uma lista de espera. Em vez disso, quando uma vaga abre, ela é oferecida a você, e você paga para ficar com ela.',
				},
				{
					type: 'steps',
					items: [
						'Em uma aula paga lotada, a página mostra **Esgotado**. Enquanto as vendas ainda estiverem abertas, clique em **Entrar na lista de espera**. Você verá **Você está na lista de espera. Se abrir uma vaga, vamos reservá-la para você e avisar.**',
						'Quando uma vaga abre e você é o primeiro da fila, você recebe uma notificação: *Abriu uma vaga em “Reformer de terça” e ela está reservada para você — pague para garanti-la*.',
						'Abra a aula na web. Ela informa quando a sua reserva termina, por exemplo *Uma vaga está reservada para você até ter., 6 de maio, 18:00. Pague para garanti-la, ou ela passa para a próxima pessoa da lista de espera.*',
						'Clique no botão para garantir a vaga (ele mostra *Garantir minha vaga* com o preço) e pague no checkout. Depois de pagar, você fica inscrito como todo mundo.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'A vaga é garantida na web. O app do celular mostra a notificação e abre a aula, mas ainda não tem checkout, então abra a aula em um navegador para pagar.',
				},
			],
		},
		{
			heading: 'Quanto tempo dura a reserva',
			blocks: [
				{
					type: 'list',
					items: [
						'Você tem 12 horas para garantir a vaga, tempo suficiente para ninguém perder uma vaga por estar dormindo.',
						'A reserva é encurtada quando as vendas daquela aula se encerram (o horário de encerramento das vendas definido pelo organizador, antes do início). Nenhuma vaga é oferecida depois que as vendas se encerram, porque ninguém poderia pagar por ela.',
						'Enquanto a sua vaga está reservada, ninguém mais pode comprá-la, mesmo que a aula pareça lotada para essas pessoas.',
						'Se você estiver no meio do checkout quando o tempo acabar, a reserva continua enquanto esse checkout estiver aberto.',
					],
				},
			],
		},
		{
			heading: 'Se você não garantir a vaga',
			blocks: [
				{
					type: 'p',
					text: 'Quando a reserva expira, a vaga é oferecida à próxima pessoa da lista de espera e você sai da lista de espera. Se ainda quiser participar, clique em **Entrar na lista de espera** de novo; você vai para o fim da fila.',
				},
				{
					type: 'p',
					text: 'Mudou de ideia enquanto ainda está esperando? Clique em **Sair da lista de espera**. O app avisa que você vai perder o seu lugar na fila; se entrar de novo depois, você vai para o fim. Se uma vaga já estiver reservada para você e você não a quiser, basta deixar a reserva expirar.',
				},
			],
		},
		{
			heading: 'Para organizadores',
			blocks: [
				{
					type: 'list',
					items: [
						'A lista de espera funciona sozinha. Defina uma **Capacidade** na aula e o resto acontece automaticamente; o prazo de 12 horas não pode ser alterado por aula.',
						'Uma vaga reservada conta na sua capacidade, então você nunca fica com mais pessoas do que tapetes.',
						'Se alguém cancelar com reembolso, a vaga dessa pessoa vai para a lista de espera. Se você cancelar uma ocorrência, ninguém da lista de espera é colocado nela: veja [[guide:cancel-a-class|Cancelar uma aula]].',
					],
				},
			],
		},
	],
	sources: {
		title: 'ff29dd616c432abb',
		summary: 'afd5b04d5200ae72',
		's0.heading': '1a4ad94ad3a45f95',
		's0.b0': 'cc59a78b4fa99e3d',
		's1.heading': '45a160f0c13ecbad',
		's1.b0': '360073628758585f',
		's1.b1': '572cda34a27eb2a9',
		's1.b2.i0': '5ee5608e87186c87',
		's1.b2.i1': '8e62e44aa4cb3c4c',
		's1.b2.i2': '2411acbf338bf29b',
		's1.b2.i3': '3fc20f1431c75da8',
		's1.b3': 'ac88ce64fbfe661e',
		's2.heading': '3120ebc77dff029c',
		's2.b0.i0': 'ac867875f2d6559e',
		's2.b0.i1': '10c7227bdd74a7f7',
		's2.b0.i2': 'ec3aaee401a8d661',
		's2.b0.i3': '115c393a06a875a2',
		's3.heading': '1c4542c4b4456638',
		's3.b0': '5f2b4c5d07b65be4',
		's3.b1': '080220c843290021',
		's4.heading': '3475448cc5eb2d77',
		's4.b0.i0': '9fc9b8683d8e30fd',
		's4.b0.i1': 'f602296c6993b85f',
		's4.b0.i2': '4d6cf70ea800fae3',
	},
};
