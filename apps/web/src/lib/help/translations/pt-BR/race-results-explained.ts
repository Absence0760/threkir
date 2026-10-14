import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-results-explained',
	title: 'Como funcionam os resultados de prova',
	summary: 'O que significam tempo bruto e tempo líquido, como as colocações são calculadas por percurso e o que dizem as marcas Manual, Organizador, DNF, DNS e pendente.',
	sections: [
		{
			heading: 'Tempo bruto e tempo líquido',
			blocks: [
				{
					type: 'list',
					items: [
						'O **Tempo bruto** é medido do momento em que o organizador deu o GO até o momento em que você cruzou a chegada. O GO é registrado pelo nosso servidor, então todos na prova compartilham a mesma largada.',
						'O **Tempo líquido** é medido de quando você pressionou Iniciar no seu próprio dispositivo até a sua chegada, incluindo as pausas.',
						'O tempo em destaque na classificação é o seu tempo bruto quando a prova teve um GO; caso contrário, é o seu tempo líquido. As colocações são calculadas a partir desse tempo em destaque.',
					],
				},
				{
					type: 'p',
					text: 'Na web, a linha menor abaixo de um tempo aparece como “bruto 41:58 · líquido 41:20”. No app do celular, um “Tempo líquido” aparece abaixo do tempo principal quando é diferente dele. Se você largou atrasado, seu tempo bruto é maior que o seu tempo líquido.',
				},
			],
		},
		{
			heading: 'As colocações são por percurso',
			blocks: [
				{
					type: 'p',
					text: 'Quando uma prova tem mais de um percurso, cada percurso tem sua própria classificação e suas próprias colocações. Quem conclui os 5K nunca é classificado junto com quem conclui os 10K. Os resultados sem percurso ficam agrupados (**Sem percurso** na página do evento, **Outros** na página ao vivo).',
				},
				{
					type: 'p',
					text: 'Só quem conclui recebe colocação. Em caso de empate, fica à frente quem teve o resultado recebido primeiro.',
				},
			],
		},
		{
			heading: 'Como a chegada foi registrada',
			blocks: [
				{
					type: 'list',
					items: [
						'**Sem marcação**: o celular ou relógio do corredor detectou a linha de chegada. Esse é o caso normal, então nem a web nem o app do celular o marcam.',
						'**Manual**: o corredor finalizou manualmente, com **Finalizar prova** depois de cobrir pelo menos 90% do percurso, ou usando **Enviar meu tempo** na web durante a prova.',
						'**Organizador** (na web, **Editado pelo organizador**): o organizador inseriu ou corrigiu este resultado, ou o corredor foi marcado como DNF quando o organizador encerrou a prova.',
					],
				},
			],
		},
		{
			heading: 'DNF e DNS',
			blocks: [
				{
					type: 'list',
					items: [
						'**DNF** (não concluiu): o corredor largou, mas não concluiu. Isso acontece quando alguém escolhe **Finalizar como DNF** antes de cobrir 90% do percurso, quando o organizador encerra a prova enquanto a pessoa ainda está no percurso, ou quando o organizador registra isso.',
						'**DNS** (não largou): registrado pelo corredor com **Registrar DNS** ou pelo organizador.',
						'Nenhum dos dois recebe colocação. Na página ao vivo, eles aparecem em **Não concluiu**.',
					],
				},
			],
		},
		{
			heading: 'Resultados pendentes',
			blocks: [
				{
					type: 'p',
					text: 'Se o organizador desativou a aprovação automática, cada novo resultado aguarda o organizador. Na página do evento na web, ele mostra **PENDENTE**, ainda sem colocação; no app do celular e na página ao vivo, mostra **Pendente**. Assim que o organizador escolhe **Aprovar**, ele assume sua colocação na classificação.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'O **Certificado** de conclusão só pode ser baixado depois que um resultado de chegada for aprovado.',
				},
			],
		},
		{
			heading: 'Algo parece errado',
			blocks: [
				{
					type: 'list',
					items: [
						'Nenhum resultado? Se o seu dispositivo estava sem sinal na chegada, ele envia o resultado quando se reconectar, em até 24 horas depois do fim da prova.',
						'Um DNF que você acha que está errado, ou um tempo incorreto? Fale com o organizador. Ele pode corrigir na web, e o resultado passa a mostrar a marca de organizador.',
					],
				},
				{
					type: 'p',
					text: 'Para o lado do corredor, veja [[guide:racing-in-a-race|Correr uma prova ao vivo]]. Organizadores: [[guide:race-day-for-hosts|Dia de prova para organizadores]].',
				},
			],
		},
	],
	sources: {
		title: 'c5d9f999ac691293',
		summary: '7d62d231e5ab41c2',
		's0.heading': 'c64bc4e8176b0753',
		's0.b0.i0': '5c206fcfa0703269',
		's0.b0.i1': 'd4a920d1ad78f899',
		's0.b0.i2': 'cf4e236435fc2502',
		's0.b1': 'a18a5324618c6db1',
		's1.heading': '280c1a73657807c5',
		's1.b0': '86d271497a41304f',
		's1.b1': '692dd04c06057463',
		's2.heading': '6e3b7d9c6cfced31',
		's2.b0.i0': '9dec22cfdf8763a9',
		's2.b0.i1': '53388c67a2b02b1b',
		's2.b0.i2': '811f16eecd7e7ab7',
		's3.heading': '6a340a4c16d7e613',
		's3.b0.i0': '6f69c4d43a38c323',
		's3.b0.i1': '3604d88945607e72',
		's3.b0.i2': 'f045b1b42c362f65',
		's4.heading': '5ed96724cf8a0430',
		's4.b0': 'f02bc0251822ab1e',
		's4.b1': 'a9bb4df966953e7a',
		's5.heading': 'badeb43244f6c195',
		's5.b0.i0': '3a602354cdf2e6f2',
		's5.b0.i1': 'b8f3e2e296b07673',
		's5.b1': '9f40f68ca81e692f',
	},
};
