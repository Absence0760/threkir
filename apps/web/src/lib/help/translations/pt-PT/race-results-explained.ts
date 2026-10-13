import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-results-explained',
	title: 'Perceber os resultados das provas',
	summary: 'O que significam o tempo bruto e o tempo líquido, como as posições são calculadas por percurso e o que dizem as marcas Manual, Organizador, DNF, DNS e pendente.',
	sections: [
		{
			heading: 'Tempo bruto e tempo líquido',
			blocks: [
				{
					type: 'list',
					items: [
						'O **Tempo bruto** é medido desde o momento em que o organizador deu a partida até ao momento em que cruzou a meta. A partida é registada pelo nosso servidor, por isso todos os participantes da prova partilham a mesma partida.',
						'O **Tempo líquido** é medido desde que premiu Iniciar no seu próprio dispositivo até à sua chegada, incluindo eventuais pausas.',
						'O tempo grande no quadro é o seu tempo bruto quando o organizador deu a partida na prova; caso contrário, é o seu tempo líquido. As posições são calculadas a partir desse tempo grande.',
					],
				},
				{
					type: 'p',
					text: 'Na web, a linha mais pequena por baixo de um tempo diz algo como “oficial 41:58 · chip 41:20”. Na app do telemóvel, aparece um tempo “Tempo real” por baixo do tempo principal quando é diferente dele. Se partiu tarde, o seu tempo bruto é maior do que o seu tempo líquido.',
				},
			],
		},
		{
			heading: 'As posições são por percurso',
			blocks: [
				{
					type: 'p',
					text: 'Quando uma prova tem mais do que um percurso, cada percurso tem o seu próprio quadro e as suas próprias posições. Quem termina os 5K nunca é classificado contra quem termina os 10K. Os resultados sem percurso são agrupados (**Sem percurso** na página do evento, **Outros** na página em direto).',
				},
				{
					type: 'p',
					text: 'Só quem termina recebe uma posição. Os empates são desfeitos a favor do resultado que chegou primeiro.',
				},
			],
		},
		{
			heading: 'Como a chegada foi registada',
			blocks: [
				{
					type: 'list',
					items: [
						'**Sem marca**: o telemóvel ou o relógio do corredor detetou a linha de meta. É o caso normal, por isso nem a web nem a app do telemóvel o assinalam.',
						'**Manual**: o corredor terminou à mão, com **Terminar prova** depois de percorrer pelo menos 90% do percurso, ou usando **Enviar o meu tempo** na web durante a prova.',
						'**Organizador** (na web, **Editado pelo organizador**): o organizador introduziu ou corrigiu este resultado, ou o corredor ficou como DNF quando o organizador encerrou a prova.',
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
						'**DNF** (não terminou): o corredor partiu mas não terminou. Acontece quando alguém escolhe **Terminar como DNF** antes de percorrer 90% do percurso, quando o organizador encerra a prova enquanto essa pessoa ainda está em prova, ou quando o organizador o regista.',
						'**DNS** (não partiu): registado pelo corredor com **Registar DNS** ou pelo organizador.',
						'Nenhum dos dois recebe posição. Na página em direto, aparecem em **Não concluiu**.',
					],
				},
			],
		},
		{
			heading: 'Resultados pendentes',
			blocks: [
				{
					type: 'p',
					text: 'Se o organizador desligou a aprovação automática, cada novo resultado fica à espera do organizador. Na página do evento na web aparece **PENDENTE**, ainda sem posição; na app do telemóvel e na página em direto aparece **Pendente**. Assim que o organizador escolhe **Aprovar**, o resultado ocupa o seu lugar no quadro.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'O **Certificado** de chegada só pode ser transferido depois de um resultado de chegada ter sido aprovado.',
				},
			],
		},
		{
			heading: 'Algo parece estar errado',
			blocks: [
				{
					type: 'list',
					items: [
						'Não há resultado nenhum? Se o seu dispositivo não tinha sinal na chegada, envia o resultado quando voltar a ligar-se, no prazo de 24 horas após o fim da prova.',
						'Um DNF que acha que está errado, ou um tempo que não bate certo? Fale com o organizador. Pode corrigi-lo na web, e o resultado passa então a mostrar a marca do organizador.',
					],
				},
				{
					type: 'p',
					text: 'Para o lado de quem corre, consulte [[guide:racing-in-a-race|Correr numa prova em direto]]. Organizadores: [[guide:race-day-for-hosts|Dia de prova para organizadores]].',
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
