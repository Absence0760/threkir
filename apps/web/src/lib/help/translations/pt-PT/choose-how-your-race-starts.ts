import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'choose-how-your-race-starts',
	title: 'Escolher como começa a sua prova',
	summary: 'GO do organizador, GO agendado ou Janela de tempo próprio: quando usar cada um, o que fazer no dia e como são aprovados os resultados.',
	sections: [
		{
			heading: 'Três formas de dar a partida',
			blocks: [
				{
					type: 'list',
					items: [
						'**GO do organizador**: prepara a prova e prime GO na linha. Use-o quando está na partida com todos, para uma partida em massa.',
						'**GO agendado**: a prova começa sozinha à hora que definir. Use-o quando a hora de partida é fixa mas pode não estar na linha, ou quer correr também. Pode atrasá-la ou cancelá-la até lá.',
						'**Janela de tempo próprio**: não há uma partida comum. Cada corredor cronometra a sua própria tentativa entre a linha de partida e a linha de chegada, a qualquer hora enquanto a janela estiver aberta. Use-a para um contrarrelógio semanal, ou para um percurso que as pessoas correm quando podem. Não há tempo oficial.',
					],
				},
				{
					type: 'p',
					text: 'Escolha em **Como a prova começa** no editor do evento, na web, num evento de corrida em grupo ou de ciclismo. A app do telemóvel consegue gerir a prova no dia (prepará-la mais cedo, atrasá-la, prolongá-la ou encerrá-la), mas a forma de partida escolhe-se na web.',
				},
			],
		},
		{
			heading: 'Definir os horários',
			blocks: [
				{
					type: 'list',
					items: [
						'GO agendado: defina a **Hora da partida** e o **Dia da partida** (no próprio dia, na véspera ou no dia seguinte ao evento). Em **Termina após, dias** e **Horas**, defina quanto tempo depois do GO a prova termina sozinha, a menos que a encerre antes.',
						'Janela de tempo próprio: defina **A janela abre às** e **Abre em** (desde a véspera do evento até uma semana depois) e quanto tempo fica aberta em **Duração da janela, dias** e **Horas**, de 1 minuto a 7 dias.',
					],
				},
				{
					type: 'p',
					text: 'Introduz e vê os horários no relógio do próprio evento, no fuso horário do evento. Na página do evento, o painel da prova mostra esse fuso horário e, quando o seu é diferente, a sua hora local ao lado.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Os horários são relativos a cada ocorrência do evento. Se mover o evento, ou uma das suas ocorrências, os horários da prova movem-se com ele. Se alterar os horários no editor, todas as ocorrências que ainda não começaram passam a usar os novos horários.',
				},
			],
		},
		{
			heading: 'No dia: GO do organizador',
			blocks: [
				{
					type: 'p',
					text: 'Preparar a prova, dar o GO e encerrá-la fica a seu cargo. Consulte [[guide:race-day-for-hosts|Dia de prova para organizadores]].',
				},
			],
		},
		{
			heading: 'No dia: GO agendado',
			blocks: [
				{
					type: 'list',
					items: [
						'Não precisa de fazer nada. A prova é configurada cerca de um dia antes da partida e começa sozinha à hora agendada.',
						'Para verificar as linhas do percurso mais cedo, escolha **Preparar mais cedo**.',
						'Antes da partida, o painel da prova mostra **Partida às** com a hora e uma contagem decrescente. Para adiar a partida, introduza os minutos e escolha **Atrasar partida**; todos os que vão são avisados de que a partida mudou. Escolha **Cancelar** para anular a prova.',
						'Depois de passada a hora de partida, a prova já não pode ser cancelada. Termina sozinha quando o tempo acabar, ou escolha **Encerrar prova** para a terminar mais cedo.',
						'Os telemóveis dos corredores fazem a contagem decrescente até à partida pelo relógio do servidor e dizem em voz alta os últimos segundos, para que todos partam ao mesmo tempo.',
					],
				},
			],
		},
		{
			heading: 'No dia: Tempo próprio',
			blocks: [
				{
					type: 'list',
					items: [
						'Não há nada para premir. A janela abre e fecha sozinha.',
						'Antes de abrir, pode escolher **Atrasar partida** ou **Cancelar**, tal como numa prova agendada.',
						'Enquanto está aberta, introduza as horas e escolha **Prolongar janela** para a manter aberta mais tempo (até 7 dias desde que abriu), ou escolha **Encerrar a janela agora** para a fechar mais cedo.',
						'Quando a janela fecha, um corredor que iniciou uma tentativa mas não enviou resultado fica marcado como DNF, tal como quando encerra qualquer prova.',
					],
				},
				{
					type: 'p',
					text: 'Cada percurso precisa de uma linha de partida e de uma linha de chegada, e estas ficam fixas para a prova quando a janela abre. Consulte [[guide:start-and-finish-lines|Linhas de partida e chegada]].',
				},
			],
		},
		{
			heading: 'Aprovar resultados de tempo próprio',
			blocks: [
				{
					type: 'p',
					text: 'Ninguém está na linha numa prova de tempo próprio, por isso os seus resultados aguardam a sua aprovação por predefinição: **Aprovar automaticamente os resultados enviados** começa desmarcado. Cada resultado aparece como **PENDENTE** até escolher **Aprovar**.',
				},
				{
					type: 'p',
					text: 'Alguns resultados ficam retidos para a sua revisão mesmo com a aprovação automática ativada: um sem passagem pela linha de partida (de uma versão antiga da app ou de um Apple Watch), um que começa fora da janela e um cujas passagens não são confirmadas pelas posições em direto do próprio corredor. Um corredor que altere o próprio tempo também volta a ficar pendente.',
				},
				{
					type: 'p',
					text: 'Um corredor pode fazer várias tentativas. Conta a sua melhor chegada cronometrada pelas duas linhas, e uma tentativa mais lenta não a substitui.',
				},
			],
		},
		{
			heading: 'Avisos de partida próxima',
			blocks: [
				{
					type: 'p',
					text: 'Cerca de 10 minutos antes de um GO agendado, todos os que vão recebem uma notificação push a dizer que a prova vai começar em breve, a menos que um lembrete do evento lhes tenha chegado na última hora. Quando atrasa uma partida, recebem uma a dizer que a partida mudou. Estes avisos nunca são enviados por e-mail.',
				},
				{
					type: 'p',
					text: 'Os corredores desligam ambos com **Prova prestes a começar**: na web, em [[route:/settings/notifications|Notificações]]; na app do telemóvel, em **Preferências**, no separador **Tu**.',
				},
			],
		},
		{
			heading: 'Os corredores precisam de uma app recente',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'As provas agendadas e de tempo próprio precisam da versão mais recente da app no telemóvel ou no relógio Wear OS. Os resultados de versões mais antigas da app e do Apple Watch ficam guardados para a sua revisão, em vez de serem recusados.',
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
		's6.b1': '125e56f45585f84e',
		's7.heading': '81f746d1e62c98a8',
		's7.b0': '00727d27f2897451',
	},
};
