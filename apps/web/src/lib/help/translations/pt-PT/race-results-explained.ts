import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-results-explained',
	title: 'Perceber os resultados das provas',
	summary: 'O que significam o tempo oficial e o tempo de chip, como as posições são calculadas, o que dizem as marcas Manual, Organizador, DNF, DNS e pendente, e como voltar a cronometrar pelo seu trajeto.',
	sections: [
		{
			heading: 'Tempo oficial e tempo de chip',
			blocks: [
				{
					type: 'list',
					items: [
						'O **Tempo oficial** é medido desde o momento em que o organizador deu o GO até ao momento em que cruzou a meta. O GO é registado pelo nosso servidor, por isso todos os participantes da prova partilham a mesma partida.',
						'O **Tempo de chip** é medido desde que atravessou a linha de partida do percurso até à sua chegada. Se o telemóvel ou o relógio não detetou nenhuma passagem pela linha de partida, conta a partir de quando premiu Iniciar no seu próprio dispositivo, incluindo eventuais pausas.',
						'Uma prova de tempo próprio não tem GO, por isso não tem tempo oficial: o quadro mostra o seu tempo de chip, da linha de partida à linha de chegada.',
						'O tempo grande no quadro é o seu tempo oficial quando a prova teve um GO; caso contrário, é o seu tempo de chip. As posições são calculadas a partir desse tempo grande.',
					],
				},
				{
					type: 'p',
					text: 'Na web, a linha mais pequena por baixo de um tempo diz algo como “oficial 41:58 · chip 41:20”. Na app do telemóvel, aparece um tempo “Chip” por baixo do tempo principal quando é diferente dele. Se partiu tarde, o seu tempo oficial é maior do que o seu tempo de chip.',
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
						'*Sem marca*: o telemóvel ou o relógio do corredor cronometrou a chegada, no momento em que atravessou a linha de chegada, ou no círculo de 30 m à volta da chegada num percurso sem linha de chegada. É o caso normal, por isso nem a web nem a app do telemóvel o assinalam.',
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
			heading: 'Voltar a cronometrar a partir do seu trajeto',
			blocks: [
				{
					type: 'p',
					text: 'Se o telemóvel falhou uma linha, se o seu resultado é um DNF que não esperava, ou se correu a prova com um Apple Watch, pode voltar a cronometrar o seu resultado a partir da corrida que gravou. Abra a corrida na web: se pertencer a uma prova, mostra **Cronometrar de novo pelo meu trajeto** com o seu resultado atual ao lado do que o seu trajeto dá.',
				},
				{
					type: 'steps',
					items: [
						'Compare as duas colunas: tempo oficial, tempo de chip e se a partida e a chegada foram cronometradas pela linha.',
						'Escolha **Cronometrar de novo o resultado** e depois **Substituir resultado**.',
					],
				},
				{
					type: 'list',
					items: [
						'Cronometra o seu trajeto pelas linhas de partida e de chegada com que a prova foi disputada, com a mesma hora de referência que o telemóvel ou o relógio usou durante a prova.',
						'Pode voltar a cronometrar até 24 horas depois de a prova terminar. Depois disso, o seu tempo, o seu percurso e a sua distância ficam bloqueados, e só o organizador pode alterar o seu tempo.',
						'Substitui um DNF, uma chegada manual e um resultado à espera de revisão. Nunca substitui um tempo definido pelo organizador nem um resultado já cronometrado pelas duas linhas; numa prova de tempo próprio, só uma tentativa mais rápida cronometrada pelas duas linhas o substitui.',
						'Se o organizador aprovar os resultados manualmente, um resultado cronometrado de novo volta a ser-lhe enviado para aprovação.',
					],
				},
			],
		},
		{
			heading: 'Algo parece estar errado',
			blocks: [
				{
					type: 'list',
					items: [
						'Não há resultado nenhum? Se o seu dispositivo não tinha sinal na chegada, envia o resultado quando voltar a ligar-se, no prazo de 24 horas após o fim da prova. Nesse mesmo prazo de 24 horas, também pode voltar a cronometrá-lo a partir do seu trajeto.',
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
