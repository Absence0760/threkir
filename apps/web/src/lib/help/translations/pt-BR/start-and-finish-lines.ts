import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'start-and-finish-lines',
	title: 'Linhas de largada e chegada',
	summary: 'O que são as linhas de largada e chegada de um percurso, como elas são colocadas para você e como movê-las, girá-las, alargá-las ou colocá-las você mesmo.',
	sections: [
		{
			heading: 'O que é uma linha',
			blocks: [
				{
					type: 'p',
					text: 'Todo percurso de uma prova tem uma linha de largada e uma linha de chegada. Uma linha atravessa o percurso em um ponto, fica voltada para o sentido em que os corredores avançam e se estende por uma distância definida para cada lado. Um corredor só a cruza quando passa por ela nesse sentido, dentro do seu alcance.',
				},
				{
					type: 'p',
					text: 'Essa é a diferença em relação a um ponto de chegada com um círculo de 30 m em volta. Um círculo conta qualquer pessoa que chegue perto: um corredor em um caminho paralelo, ou na ida de um percurso de ida e volta que retorna pelo mesmo caminho. Uma linha não conta, porque essas pessoas nunca passam por ela no sentido certo.',
				},
			],
		},
		{
			heading: 'Linhas colocadas para você',
			blocks: [
				{
					type: 'p',
					text: 'Quando um percurso tem uma rota, ele recebe as duas linhas a partir dela. A linha de largada fica no primeiro ponto da rota, voltada no sentido da rota. A linha de chegada fica no último ponto, voltada para o sentido em que a rota chega. Cada uma se estende 15 m para cada lado. Elas acompanham a rota: se você mudar a rota, elas se movem junto.',
				},
				{
					type: 'p',
					text: 'As linhas aparecem depois que o evento é salvo com pelo menos um percurso. Abra o evento, escolha **Editar evento** e encontre **Linhas de largada e chegada**. Cada percurso tem um mapa e, para cada linha, uma entrada que diz de onde ela veio: **Da rota**, **Colocada por um organizador** ou **Nenhuma**.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se o dono da rota tiver uma zona de privacidade sobre o início ou o fim da rota, essa ponta fica oculta para todos os demais, então ela não recebe linha. Coloque essa linha você mesmo.',
				},
			],
		},
		{
			heading: 'Mover, girar ou alargar uma linha',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ao lado de **Linha de largada** ou **Linha de chegada**, escolha **Editar**.',
						'No mapa, arraste o meio da linha para movê-la e arraste a alça dela para girá-la. Se o mapa não estiver carregado, escolha **Carregar mapa**, ou dispense o mapa e digite os valores.',
						'Ou digite a **Latitude**, a **Longitude** e a **Direção (graus)**. A direção é o sentido em que os corredores cruzam, em sentido horário a partir do norte: 0 é norte, 90 é leste, 180 é sul e 270 é oeste.',
						'Defina o **Alcance de cada lado**, de 5 a 100 m. Deixe-o largo o bastante para cobrir toda a rua ou trilha, com um pouco de folga.',
						'Escolha **Salvar linha**.',
					],
				},
				{
					type: 'p',
					text: 'Cada linha é salva por conta própria, na hora; você não precisa salvar o evento. Uma linha que você moveu mostra **Colocada por um organizador**. Escolha **Voltar à rota** para devolvê-la ao lugar em que a rota a coloca.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Uma linha que você colocou fica exatamente onde você a deixou, mesmo que depois você mude a rota do percurso. Depois de mudar uma rota, confira os avisos abaixo de cada linha.',
				},
			],
		},
		{
			heading: 'Avisos no editor',
			blocks: [
				{
					type: 'list',
					items: [
						'A linha está a mais de 100 m da rota do percurso. Confira se ela está no lugar certo.',
						'A linha está voltada contra a rota, então os corredores que seguirem a rota a cruzariam no sentido contrário. Gire-a.',
						'A rota cruza a própria linha de chegada antes do fim, como acontece em um percurso de voltas ou em uma pista. A chegada pela linha fica então desativada para esse percurso, e os corredores concluem pressionando Parar ou Finalizar.',
					],
				},
			],
		},
		{
			heading: 'Percursos sem rota',
			blocks: [
				{
					type: 'p',
					text: 'Um percurso sem rota não tem linhas até você colocá-las. Escolha **Colocar linha de largada** ou **Colocar linha de chegada**. Se você já tiver levado o mapa até o local, a linha começa no centro do mapa; caso contrário, digite a posição dela. Depois defina a direção e o alcance e escolha **Salvar linha**. **Remover linha** retira de novo uma linha que você colocou.',
				},
			],
		},
		{
			heading: 'As linhas são fixadas quando a prova começa',
			blocks: [
				{
					type: 'p',
					text: 'Quando você prepara uma prova (no caso de uma prova de tempo próprio, quando a janela dela abre), as linhas de cada percurso são copiadas para essa prova. Assim, todos os corredores dela cruzam as mesmas linhas, seja qual for a mudança durante a prova. Uma alteração que você fizer depois vale a partir da próxima prova. A página do evento e a página da prova ao vivo mostram as linhas com que a prova foi preparada.',
				},
			],
		},
		{
			heading: 'Verificações antes de uma prova',
			blocks: [
				{
					type: 'p',
					text: 'Antes de uma prova ser preparada, as linhas de todos os percursos são verificadas, na web e no app do celular. Um aviso permite **Preparar mesmo assim**; um problema marcado com **Precisa corrigir:** impede que a prova seja preparada até você corrigi-lo no editor do evento na web.',
				},
				{
					type: 'list',
					items: [
						'Um percurso sem linha de chegada e sem ponto de chegada: um aviso, porque os corredores dele concluem manualmente. Em uma prova de tempo próprio, é preciso corrigir.',
						'Um percurso sem linha de largada: em uma prova de tempo próprio, é preciso corrigir. As outras provas podem começar sem ela.',
						'Uma rota que cruza a própria linha de chegada antes do fim: um aviso, porque a chegada pela linha fica desativada para esse percurso. Em uma prova de tempo próprio, é preciso corrigir.',
						'Uma linha a mais de 100 m da rota: um aviso em qualquer tipo de prova.',
					],
				},
				{
					type: 'p',
					text: 'O tipo de prova que você está conduzindo é definido em **Como a corrida começa**; veja [[guide:choose-how-your-race-starts|Escolher como sua prova começa]].',
				},
			],
		},
	],
	sources: {
		title: 'e32b975b30a0bfdf',
		summary: '007484d24c448df5',
		's0.heading': 'b2178bb9e4c07f85',
		's0.b0': '7b22e9bee9ea6e44',
		's0.b1': 'e18c2ba36732dafb',
		's1.heading': '6ae01aac1742fa11',
		's1.b0': '98879a39846cccd2',
		's1.b1': '1121c7b877f6a658',
		's1.b2': '5d09b8607f6a2f22',
		's2.heading': 'b839a49fc88eb9bb',
		's2.b0.i0': 'f9a4dd08d366b730',
		's2.b0.i1': '0bfc28ecb00a6d5b',
		's2.b0.i2': '29eaf88dee6df1d8',
		's2.b0.i3': '082f59f63580a00b',
		's2.b0.i4': '008936c6ea875617',
		's2.b1': 'e6292e6047487d65',
		's2.b2': '5bad76f945b81e03',
		's3.heading': '49bbc9db5d4c7163',
		's3.b0.i0': 'c519f8cea9bd87d0',
		's3.b0.i1': 'e08a656a24f1ed58',
		's3.b0.i2': 'aa848004795cf7a1',
		's4.heading': '3bd16f8003e613ef',
		's4.b0': 'adfbcab88a7c3e90',
		's5.heading': 'be581f997710aa1d',
		's5.b0': 'b691f01dae47a921',
		's6.heading': 'a1cbd797f4858538',
		's6.b0': '3ab85eab34b17f4c',
		's6.b1.i0': 'e5b89e5070aad84a',
		's6.b1.i1': '2d67c55e24d207a9',
		's6.b1.i2': '1ecbd8a36af71c78',
		's6.b1.i3': '84f19ca583307307',
		's6.b2': 'cfbf64534e49a993',
	},
};
