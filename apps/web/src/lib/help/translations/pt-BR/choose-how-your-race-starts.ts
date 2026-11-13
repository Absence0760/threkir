import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'choose-how-your-race-starts',
	title: 'Escolher como sua prova começa',
	summary: 'GO do organizador, GO agendado ou Janela de tempo próprio: quando usar cada um, o que você faz no dia e como os resultados são aprovados.',
	sections: [
		{
			heading: 'Três formas de largar',
			blocks: [
				{
					type: 'list',
					items: [
						'**GO do organizador**: você prepara a prova e aperta GO na linha. Use quando você estiver na largada com todo mundo, para uma largada em massa.',
						'**GO agendado**: a prova começa sozinha no horário que você definir. Use quando o horário de largada for fixo, mas você talvez não esteja na linha ou queira correr também. Até lá, você pode atrasá-la ou cancelá-la.',
						'**Janela de tempo próprio**: não há largada conjunta. Cada corredor cronometra a própria tentativa entre a linha de largada e a linha de chegada, a qualquer momento enquanto a janela estiver aberta. Use para um contrarrelógio semanal ou para um percurso que as pessoas correm quando podem. Não há tempo bruto.',
					],
				},
				{
					type: 'p',
					text: 'Escolha em **Como a corrida começa** no editor do evento na web, para um evento de corrida em grupo ou de ciclismo. O app do celular pode conduzir a prova no dia (prepará-la antes, atrasá-la, estendê-la ou encerrá-la), mas a forma de largada é escolhida na web.',
				},
			],
		},
		{
			heading: 'Definir os horários',
			blocks: [
				{
					type: 'list',
					items: [
						'GO agendado: defina o **Horário da largada** e o **Dia da largada** (no dia, na véspera ou no dia seguinte ao evento). Em **Termina após, dias** e **Horas**, defina quanto tempo depois do GO a prova termina sozinha, a menos que você a encerre antes.',
						'Janela de tempo próprio: defina **A janela abre às** e **Abre em** (da véspera do evento até uma semana depois dele) e quanto tempo ela fica aberta em **Duração da janela, dias** e **Horas**, de 1 minuto a 7 dias.',
					],
				},
				{
					type: 'p',
					text: 'Você digita e vê os horários no relógio do próprio evento, no fuso horário dele. Na página do evento, o painel da prova mostra esse fuso horário e, quando o seu é diferente, o seu horário ao lado.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Os horários são guardados em relação a cada ocorrência do evento. Se você mover o evento, ou uma ocorrência dele, os horários da prova se movem junto. Se você mudar os horários no editor, toda ocorrência que ainda não começou passa a usar os novos horários.',
				},
			],
		},
		{
			heading: 'No dia: GO do organizador',
			blocks: [
				{
					type: 'p',
					text: 'Você prepara a prova, dá o GO e a encerra você mesmo. Veja [[guide:race-day-for-hosts|Dia de prova para organizadores]].',
				},
			],
		},
		{
			heading: 'No dia: GO agendado',
			blocks: [
				{
					type: 'list',
					items: [
						'Você não precisa fazer nada. A prova é configurada cerca de um dia antes da largada e começa sozinha no horário agendado.',
						'Para conferir as linhas do percurso mais cedo, escolha **Preparar mais cedo**.',
						'Antes da largada, o painel da prova mostra **Largada às** com o horário e uma contagem regressiva. Para adiar a largada, informe os minutos e escolha **Atrasar largada**; todos que vão participar são avisados de que a largada mudou. Escolha **Cancelar** para cancelar a prova.',
						'Depois que o horário de largada passa, a prova não pode mais ser cancelada. Ela termina sozinha quando o tempo dela acaba, ou escolha **Encerrar corrida** para encerrá-la antes.',
						'Os celulares dos corredores fazem a contagem regressiva até a largada pelo relógio do servidor e falam os últimos segundos, para que todos larguem juntos.',
					],
				},
			],
		},
		{
			heading: 'No dia: tempo próprio',
			blocks: [
				{
					type: 'list',
					items: [
						'Não há nada para apertar. A janela abre e fecha sozinha.',
						'Antes de ela abrir, você pode usar **Atrasar largada** ou **Cancelar**, como em uma prova agendada.',
						'Enquanto ela estiver aberta, informe as horas e escolha **Estender janela** para mantê-la aberta por mais tempo (até 7 dias a partir de quando abriu), ou escolha **Encerrar a janela agora** para fechá-la antes.',
						'Quando a janela fecha, um corredor que começou uma tentativa mas não enviou resultado é marcado como DNF, como quando você encerra qualquer prova.',
					],
				},
				{
					type: 'p',
					text: 'Todo percurso precisa de uma linha de largada e de uma linha de chegada, e elas são fixadas para a prova quando a janela abre. Veja [[guide:start-and-finish-lines|Linhas de largada e chegada]].',
				},
			],
		},
		{
			heading: 'Aprovar resultados de tempo próprio',
			blocks: [
				{
					type: 'p',
					text: 'Ninguém fica na linha em uma prova de tempo próprio, então, por padrão, os resultados aguardam você: **Aprovar automaticamente os resultados enviados** começa desmarcado. Cada resultado aparece como **PENDENTE** até você escolher **Aprovar**.',
				},
				{
					type: 'p',
					text: 'Alguns resultados ficam retidos para sua revisão mesmo com a aprovação automática ativada: um sem cruzamento da linha de largada (de um app antigo ou de um Apple Watch), um que começa fora da janela e um cujos cruzamentos não são confirmados pelas próprias posições ao vivo do corredor. Um corredor que altera o próprio tempo também volta para pendente.',
				},
				{
					type: 'p',
					text: 'Um corredor pode fazer várias tentativas. Vale a melhor chegada cronometrada pelas duas linhas, e uma tentativa mais lenta não a substitui.',
				},
			],
		},
		{
			heading: 'Avisos de largada próxima',
			blocks: [
				{
					type: 'p',
					text: 'Cerca de 10 minutos antes de um GO agendado, todos que vão participar recebem uma notificação push de que a prova vai começar em breve, a menos que um lembrete do evento tenha chegado a eles na última hora. Quando você atrasa uma largada, eles recebem uma avisando que ela mudou. Esses avisos nunca são enviados por e-mail.',
				},
				{
					type: 'p',
					text: 'Os corredores desativam os dois com **Corrida prestes a começar**: na web, em [[route:/settings/notifications|Notificações]]; no app do celular, em **Notificações** na aba **Você**.',
				},
			],
		},
		{
			heading: 'Os corredores precisam de um app atualizado',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Provas agendadas e de tempo próprio precisam da versão mais recente do app no celular ou no relógio Wear OS. Os resultados de apps antigos e do Apple Watch ficam guardados para sua revisão em vez de serem recusados.',
				},
			],
		},
	],
	sources: {
		title: '8dd0bfbefd97b39d',
		summary: '5f79511dd816ce5e',
		's0.heading': '9b26470e1beae1e9',
		's0.b0.i0': '653b79ec7d550dc5',
		's0.b0.i1': '6824deac8c3239bb',
		's0.b0.i2': '86642ad5f00798d9',
		's0.b1': '8ec9d026a8e162d9',
		's1.heading': '8ec1ca546316bf44',
		's1.b0.i0': '7f4cdf51f946ad7a',
		's1.b0.i1': 'e945e787986a825b',
		's1.b1': 'dc8ad2296857c406',
		's1.b2': 'f73aee6a8e52f86d',
		's2.heading': '3b72a06be5feeca1',
		's2.b0': 'f8eb6df29239da40',
		's3.heading': '2e53337b73ea8f70',
		's3.b0.i0': '0cd2e7973bd13122',
		's3.b0.i1': 'bb292e4077fab06b',
		's3.b0.i2': '1001bcee9a695cbd',
		's3.b0.i3': 'ad3f370a0b11c0ea',
		's3.b0.i4': '8469b5a684fd410f',
		's4.heading': '5b67193948e22e2a',
		's4.b0.i0': '689b27335b1205f7',
		's4.b0.i1': '8835ede766aaa683',
		's4.b0.i2': '92ab0d9a0804d8f9',
		's4.b0.i3': 'fe1797aedc22317e',
		's4.b1': 'fe8c69f32f52d3b4',
		's5.heading': '32e61b0e9e8b093c',
		's5.b0': 'd72ed9b7c3434bf2',
		's5.b1': '8270611445444242',
		's5.b2': '80fde57d63447dcd',
		's6.heading': 'b0f6668439cdc509',
		's6.b0': '7f18ce5f91bea911',
		's6.b1': '75dcfe5f36ba4e0a',
		's7.heading': '81f746d1e62c98a8',
		's7.b0': '00727d27f2897451',
	},
};
