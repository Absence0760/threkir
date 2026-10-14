import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'waitlist-and-claim-window',
	title: 'Listas de espera e o prazo de 12 horas para garantir o lugar',
	summary: 'Como funciona entrar numa aula cheia, como um lugar libertado fica reservado para si durante 12 horas numa aula paga e o que acontece se não o garantir.',
	sections: [
		{
			heading: 'Aulas gratuitas: entra automaticamente',
			blocks: [
				{
					type: 'p',
					text: 'Quando uma aula gratuita com **Capacidade** está cheia, premir **Eu vou** coloca-o na lista de espera e a sua confirmação mostra **Na lista de espera**. Quando alguém desiste, a primeira pessoa da lista de espera passa automaticamente para **Confirmado**; não há nada a garantir. Funciona na web e na app do telemóvel.',
				},
			],
		},
		{
			heading: 'Aulas pagas: o lugar é reservado e depois paga',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'As aulas pagas ainda não estão disponíveis: precisam da conta Stripe do organizador ligada e da inscrição paga ativada pela plataforma. Tudo o que está nesta secção aplica-se quando estiverem.',
				},
				{
					type: 'p',
					text: 'Ninguém é cobrado só por estar numa lista de espera. Em vez disso, quando abre um lugar, este é-lhe oferecido e paga para o garantir.',
				},
				{
					type: 'steps',
					items: [
						'Numa aula paga cheia, a página mostra **Esgotado**. Enquanto as vendas estiverem abertas, prima **Entrar na lista de espera**. Verá **Está na lista de espera. Se abrir um lugar, reservamo-lo para si e avisamos.**',
						'Quando abre um lugar e é o primeiro da fila, recebe uma notificação: *Abriu um lugar em “Reformer de terça” e está reservado para si — pague para o garantir*.',
						'Abra a aula na web. Indica quando termina a sua reserva, por exemplo *Tem um lugar reservado até terça-feira, 6 de maio às 18:00. Pague para o garantir, ou passa para a pessoa seguinte da lista de espera.*',
						'Prima o botão para garantir o lugar (diz *Garantir o meu lugar* com o preço) e pague na página de pagamento. Depois de pagar, fica inscrito como todos os outros.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Garantir o lugar faz-se na web. A app do telemóvel mostra a notificação e abre a aula, mas ainda não tem pagamento, por isso abra a aula num navegador para pagar.',
				},
			],
		},
		{
			heading: 'Quanto tempo dura a reserva',
			blocks: [
				{
					type: 'list',
					items: [
						'Tem 12 horas para garantir o lugar, tempo suficiente para que ninguém perca um lugar por estar a dormir.',
						'A reserva é encurtada quando as vendas dessa aula encerram (a hora de encerramento de vendas definida pelo organizador antes do início). Nenhum lugar é oferecido depois de as vendas encerrarem, porque ninguém o poderia pagar.',
						'Enquanto o seu lugar estiver reservado, mais ninguém o pode comprar, mesmo que a aula pareça cheia a essas pessoas.',
						'Se estiver a meio do pagamento quando o tempo acabar, a reserva mantém-se enquanto esse pagamento estiver aberto.',
					],
				},
			],
		},
		{
			heading: 'Se não o garantir',
			blocks: [
				{
					type: 'p',
					text: 'Quando a reserva expira, o lugar é oferecido à pessoa seguinte da lista de espera e sai da lista de espera. Se ainda quiser entrar, prima novamente **Entrar na lista de espera**; passa para o fim da fila.',
				},
				{
					type: 'p',
					text: 'Mudou de ideias enquanto ainda espera? Prima **Sair da lista de espera**. É avisado de que perderá o seu lugar na fila; se voltar a entrar mais tarde, passa para o fim. Se já tiver um lugar reservado e não o quiser, basta deixar a reserva expirar.',
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
						'Um lugar reservado conta para a sua capacidade, por isso nunca acaba com mais pessoas do que tapetes.',
						'Se alguém cancelar com reembolso, o seu lugar passa para a lista de espera. Se cancelar uma ocorrência, ninguém da lista de espera é colocado nela: consulte [[guide:cancel-a-class|Cancelar uma aula]].',
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
