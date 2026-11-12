import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'recurring-events',
	title: 'Configurar um evento recorrente do clube',
	summary: 'Transforme um evento do clube em uma série semanal, quinzenal ou mensal, confirme presença em uma única data e cancele uma ocorrência sem mexer nas outras.',
	sections: [
		{
			heading: 'Criar a série',
			blocks: [
				{
					type: 'p',
					text: 'Proprietários, administradores e organizadores de eventos do clube podem criar eventos. Um evento recorrente é um único evento que se repete, então tudo o que você preencher vale para todas as datas.',
				},
				{
					type: 'steps',
					items: [
						'Abra o seu clube na web e selecione **Novo evento**.',
						'Preencha o **Título**, o **Horário de início** e os outros detalhes como em um evento único. O horário de início que você escolher é a primeira data da série.',
						'Em **Repetição**, escolha **Semanal**, **A cada 2 semanas** ou **Mensal** em vez de **Único**.',
						'Para uma série semanal ou quinzenal, escolha os dias da semana em **Nestes dias:**. Uma série mensal se repete no mesmo dia do mês da data de início.',
						'Decida quando a série para: defina **Termina em** com uma data, **Termina após** com um número de ocorrências, ou os dois, e vale o que vier primeiro. Deixe os dois vazios e ela continua se repetindo.',
						'Selecione **Criar evento**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'O padrão de repetição só pode ser escolhido enquanto o evento está sendo criado. **Editar evento** muda o título, o horário, o ponto de encontro e outros detalhes de toda a série, mas não a frequência com que ela se repete.',
				},
				{
					type: 'p',
					text: 'No app para celular, toque em **Criar evento** na aba **Eventos** do clube e escolha **Semanal**, **Quinzenal** ou **Mensal** em **Recorrência**. O celular repete o evento no dia da semana da data de início e não tem data de término nem contagem de ocorrências, então use a web se a série precisar parar.',
				},
			],
		},
		{
			heading: 'Confirmar presença em uma data',
			blocks: [
				{
					type: 'p',
					text: 'Cada data de uma série tem as próprias confirmações de presença, lista de participantes, capacidade e resultados.',
				},
				{
					type: 'steps',
					items: [
						'Abra o evento e use **Escolha uma ocorrência** para escolher a data. As próximas datas aparecem, e **Mostrar as 12 próximas** (o número indica quantas datas faltam) expande para todas as datas futuras do próximo ano.',
						'Escolha **Eu vou**, **Talvez** ou **Não posso** para essa data.',
					],
				},
				{
					type: 'p',
					text: 'Para colocar as datas no seu próprio calendário, selecione **Adicionar ao calendário**. Em uma série, você pode escolher **Adicionar esta ocorrência** para uma data ou **Adicionar toda a série** para todas as datas.',
				},
			],
		},
		{
			heading: 'Cancelar uma ocorrência',
			blocks: [
				{
					type: 'p',
					text: 'Se uma data não puder acontecer, cancele só essa data e deixe o resto da série como está.',
				},
				{
					type: 'steps',
					items: [
						'Abra o evento na web e escolha a data que você precisa cancelar.',
						'Selecione **Cancelar esta ocorrência**.',
						'Adicione um **Motivo (opcional)**, como um percurso alagado ou um feriado, e confirme. Selecione **Manter** se mudar de ideia.',
					],
				},
				{
					type: 'p',
					text: 'Todos que confirmaram presença nessa data, sejam confirmados, talvez ou na lista de espera, recebem uma notificação. A data mostra **Esta ocorrência foi cancelada.** e ninguém pode confirmar presença nela. Para trazê-la de volta, abra a data e selecione **Restabelecer esta ocorrência**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Cancelar e restabelecer uma data só é possível na web. **Excluir evento** remove todas as ocorrências da série, não só uma.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se o evento for uma aula paga, cancelar uma ocorrência reembolsa integralmente todos os inscritos nela. Veja [[guide:host-a-paid-yoga-class|Oferecer uma aula paga de ioga]].',
				},
			],
		},
	],
	sources: {
		title: 'e613c3be8d106d58',
		summary: '16e60fe00d2cd802',
		's0.heading': '718e1069f51a2cb4',
		's0.b0': '3db51494677d6358',
		's0.b1.i0': '7b361a4f9398e384',
		's0.b1.i1': '17734b394312df43',
		's0.b1.i2': '0f73dbb856a7fa67',
		's0.b1.i3': 'a002823ae62a3df3',
		's0.b1.i4': 'e54a7bd9afd1d160',
		's0.b1.i5': 'ec48c553acdf742f',
		's0.b2': 'df7167c739a9ea9e',
		's0.b3': 'c40bdc990b5425db',
		's1.heading': 'd0f06618475ee3d1',
		's1.b0': 'fb3d5e80f695a45d',
		's1.b1.i0': 'af04da638393359f',
		's1.b1.i1': 'e208d82edea8262f',
		's1.b2': 'c2477719db027ba7',
		's2.heading': 'f95356ca142cc32c',
		's2.b0': '2836a3e020560d5f',
		's2.b1.i0': 'db8f532e330056ff',
		's2.b1.i1': '0c4ddfc33914c615',
		's2.b1.i2': 'fa7eaa32d4fdc37a',
		's2.b2': 'b34bc386e0fc3cb4',
		's2.b3': 'c1fb4f63833b6418',
		's2.b4': 'dfb7d75cf658eb0a',
	},
};
