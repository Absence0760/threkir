import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-results-explained',
	title: 'Como funcionam os resultados de prova',
	summary: 'O que significam tempo bruto e tempo líquido, como as colocações são calculadas, o que dizem as marcas Manual, Organizador, DNF, DNS e pendente, e como recronometrar pelo seu trajeto.',
	sections: [
		{
			heading: 'Tempo bruto e tempo líquido',
			blocks: [
				{
					type: 'list',
					items: [
						'O **Tempo bruto** é medido do momento em que o organizador deu o GO até o momento em que você cruzou a chegada. O GO é registrado pelo nosso servidor, então todos na prova compartilham a mesma largada.',
						'O **Tempo líquido** é medido de quando você cruzou a linha de largada do percurso até a sua chegada. Se seu celular ou relógio não detectou nenhum cruzamento da linha de largada, ele conta a partir de quando você pressionou Iniciar no seu próprio dispositivo, incluindo as pausas.',
						'Uma prova de tempo próprio não tem GO, então não tem tempo bruto: a classificação dela mostra seu tempo líquido, da linha de largada até a linha de chegada.',
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
						'*Sem marcação*: o celular ou relógio do corredor registrou a chegada, no momento em que ele cruzou a linha de chegada, ou no círculo de 30 m em volta da chegada, em um percurso sem linha de chegada. Esse é o caso normal, então nem a web nem o app do celular o marcam.',
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
			heading: 'Recronometrar pelo seu trajeto',
			blocks: [
				{
					type: 'p',
					text: 'Se o seu celular não detectou uma linha, se o seu resultado é um DNF que você não esperava ou se você correu a prova com um Apple Watch, é possível cronometrar seu resultado de novo a partir da corrida que você gravou. Abra a corrida na web: se ela pertence a uma prova, mostra **Recronometrar pelo meu trajeto** com seu resultado atual ao lado do resultado que o seu trajeto dá.',
				},
				{
					type: 'steps',
					items: [
						'Confira as duas colunas: tempo bruto, tempo líquido e se a largada e a chegada foram cronometradas pela linha.',
						'Escolha **Recronometrar resultado** e depois **Substituir resultado**.',
					],
				},
				{
					type: 'list',
					items: [
						'Ele cronometra seu trajeto pelas linhas de largada e chegada com que a prova foi disputada, usando o mesmo horário de referência que seu celular ou relógio usou durante a prova.',
						'Você pode recronometrar até 24 horas depois do fim da prova. Depois disso, seu tempo, seu percurso e sua distância ficam bloqueados, e só o organizador pode mudar seu tempo.',
						'Ele substitui um DNF, um tempo de chegada manual e um resultado aguardando revisão. Ele nunca substitui um tempo definido pelo organizador nem um resultado já cronometrado pelas duas linhas; em uma prova de tempo próprio, só uma tentativa mais rápida cronometrada pelas duas linhas o substitui.',
						'Se o organizador aprovar os resultados manualmente, um resultado recronometrado volta para a aprovação dele.',
					],
				},
			],
		},
		{
			heading: 'Algo parece errado',
			blocks: [
				{
					type: 'list',
					items: [
						'Nenhum resultado? Se o seu dispositivo estava sem sinal na chegada, ele envia o resultado quando se reconectar, em até 24 horas depois do fim da prova. Nessas mesmas 24 horas, você também pode recronometrá-lo pelo seu trajeto.',
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
		summary: '184c2d298bd26fe6',
		's0.heading': 'c64bc4e8176b0753',
		's0.b0.i0': '5c206fcfa0703269',
		's0.b0.i1': 'cb9512f304721331',
		's0.b0.i2': 'd7cbf99a35b6a2ef',
		's0.b0.i3': 'cf4e236435fc2502',
		's0.b1': 'a18a5324618c6db1',
		's1.heading': '280c1a73657807c5',
		's1.b0': '86d271497a41304f',
		's1.b1': '692dd04c06057463',
		's2.heading': '6e3b7d9c6cfced31',
		's2.b0.i0': '8376fb6f54bdb6f2',
		's2.b0.i1': '53388c67a2b02b1b',
		's2.b0.i2': '811f16eecd7e7ab7',
		's3.heading': '6a340a4c16d7e613',
		's3.b0.i0': '6f69c4d43a38c323',
		's3.b0.i1': '3604d88945607e72',
		's3.b0.i2': 'f045b1b42c362f65',
		's4.heading': '5ed96724cf8a0430',
		's4.b0': 'f02bc0251822ab1e',
		's4.b1': 'a9bb4df966953e7a',
		's5.heading': '58d90ac423027da2',
		's5.b0': '8fe61e9de9317b69',
		's5.b1.i0': 'd6fc360bf0506c2c',
		's5.b1.i1': 'b0eb18e5a8270886',
		's5.b2.i0': '7b1ea13025902315',
		's5.b2.i1': 'a97c00d0cbdf91fc',
		's5.b2.i2': '8a9c94b45aba53b2',
		's5.b2.i3': '84812a40e9aafb58',
		's6.heading': 'badeb43244f6c195',
		's6.b0.i0': '9afe7b467f14e81b',
		's6.b0.i1': 'b8f3e2e296b07673',
		's6.b1': '9f40f68ca81e692f',
	},
};
