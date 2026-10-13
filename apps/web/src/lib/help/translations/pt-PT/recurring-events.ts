import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'recurring-events',
	title: 'Configurar um evento recorrente do clube',
	summary: 'Transforme um evento do clube numa série semanal, quinzenal ou mensal, confirme presença numa só data e cancele uma ocorrência sem mexer nas restantes.',
	sections: [
		{
			heading: 'Criar a série',
			blocks: [
				{
					type: 'p',
					text: 'Os proprietários, administradores e organizadores de eventos de um clube podem criar eventos. Um evento recorrente é um único evento que se repete, por isso tudo o que preencher aplica-se a todas as datas.',
				},
				{
					type: 'steps',
					items: [
						'Abra o seu clube na web e selecione **Novo evento**.',
						'Preencha o **Título**, a **Hora de início** e os restantes detalhes como faria num evento único. A hora de início que escolher é a primeira data da série.',
						'Em **Repetição**, escolha **Semanal**, **A cada 2 semanas** ou **Mensal** em vez de **Único**.',
						'Numa série semanal ou quinzenal, escolha os dias da semana em **Nestes dias:**. Uma série mensal repete-se no mesmo dia do mês da data de início.',
						'Decida quando a série termina: defina uma data em **Termina em**, um número de ocorrências em **Termina após**, ou ambos, e vale o que chegar primeiro. Se deixar ambos vazios, a série continua a repetir-se.',
						'Selecione **Criar evento**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'A frequência de repetição só pode ser escolhida enquanto o evento está a ser criado. **Editar evento** altera o título, a hora, o ponto de encontro e outros detalhes de toda a série, mas não a frequência com que se repete.',
				},
				{
					type: 'p',
					text: 'Na app do telemóvel, toque em **Criar evento** no separador **Eventos** do clube e escolha **Semanal**, **Quinzenal** ou **Mensal** em **Recorrência**. O telemóvel repete o evento no dia da semana da data de início e não tem data de fim nem número de ocorrências, por isso use a web se a série tiver de terminar.',
				},
			],
		},
		{
			heading: 'Confirmar presença numa data',
			blocks: [
				{
					type: 'p',
					text: 'Cada data de uma série tem as suas próprias confirmações de presença, lista de participantes, capacidade e resultados.',
				},
				{
					type: 'steps',
					items: [
						'Abra o evento e use **Escolha uma ocorrência** para escolher a data. São mostradas as próximas datas, e **Mostrar todas** expande a lista a todas as datas do próximo ano.',
						'Escolha **Eu vou**, **Talvez** ou **Não posso** para essa data.',
					],
				},
				{
					type: 'p',
					text: 'Para pôr as datas no seu próprio calendário, selecione **Adicionar ao calendário**. Numa série, pode escolher **Adicionar esta ocorrência** para uma só data ou **Adicionar toda a série** para todas as datas.',
				},
			],
		},
		{
			heading: 'Cancelar uma ocorrência',
			blocks: [
				{
					type: 'p',
					text: 'Se uma data não se puder realizar, cancele apenas essa data e deixe o resto da série como está.',
				},
				{
					type: 'steps',
					items: [
						'Abra o evento na web e escolha a data que precisa de cancelar.',
						'Selecione **Cancelar esta ocorrência**.',
						'Adicione um **Motivo (opcional)**, como um percurso inundado ou um feriado, e confirme. Selecione **Manter** se mudar de ideias.',
					],
				},
				{
					type: 'p',
					text: 'Todas as pessoas que confirmaram presença nessa data, seja como confirmadas, talvez ou na lista de espera, recebem uma notificação. A data mostra **Esta ocorrência foi cancelada.** e ninguém pode confirmar presença nela. Para a repor, abra a data e selecione **Restabelecer esta ocorrência**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Cancelar e restabelecer uma data só é possível na web. **Eliminar evento** remove todas as ocorrências da série, não apenas uma.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se o evento for uma aula paga, cancelar uma ocorrência reembolsa na totalidade todas as pessoas inscritas nela. Consulte [[guide:host-a-paid-yoga-class|Organizar uma aula paga de ioga]].',
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
		's1.b1.i0': '11bf9a8e15037b7c',
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
