import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'start-and-finish-lines',
	title: 'Linhas de partida e chegada',
	summary: 'O que são as linhas de partida e chegada de um percurso, como são colocadas automaticamente e como pode movê-las, rodá-las, alargá-las ou colocá-las manualmente.',
	sections: [
		{
			heading: 'O que é uma linha',
			blocks: [
				{
					type: 'p',
					text: 'Cada percurso de uma prova tem uma linha de partida e uma linha de chegada. Uma linha atravessa o percurso num ponto, está virada para o sentido em que os corredores seguem e estende-se uma distância definida para cada lado. Um corredor só a atravessa se passar por ela nesse sentido, dentro do seu alcance.',
				},
				{
					type: 'p',
					text: 'É essa a diferença em relação a um ponto de chegada com um círculo de 30 m à volta. Um círculo conta qualquer pessoa que se aproxime: um corredor num caminho paralelo, ou na ida de um percurso de ida e volta que regressa pelo mesmo caminho. Uma linha não, porque esses corredores nunca a atravessam no sentido certo.',
				},
			],
		},
		{
			heading: 'Linhas colocadas automaticamente',
			blocks: [
				{
					type: 'p',
					text: 'Quando um percurso tem rota, recebe as duas linhas a partir dela. A linha de partida fica no primeiro ponto da rota, virada ao longo da rota. A linha de chegada fica no último ponto, virada no sentido em que a rota chega. Cada uma estende-se 15 m para cada lado. As linhas acompanham a rota: se alterar a rota, movem-se com ela.',
				},
				{
					type: 'p',
					text: 'As linhas aparecem quando o evento é guardado com pelo menos um percurso. Abra o evento, escolha **Editar evento** e encontre **Linhas de partida e chegada**. Cada percurso tem um mapa e uma entrada para cada linha, que indica de onde veio a linha: **Da rota**, **Colocada por um organizador** ou **Nenhuma**.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se o proprietário da rota tiver uma zona de privacidade sobre o início ou o fim da rota, essa extremidade fica oculta para todas as outras pessoas, por isso não recebe linha. Coloque essa linha manualmente.',
				},
			],
		},
		{
			heading: 'Mover, rodar ou alargar uma linha',
			blocks: [
				{
					type: 'steps',
					items: [
						'Ao lado de **Linha de partida** ou **Linha de chegada**, escolha **Editar**.',
						'No mapa, arraste o meio da linha para a mover e arraste a pega para a rodar. Se o mapa estiver desligado, escolha **Carregar mapa**, ou dispense o mapa e escreva os valores.',
						'Ou escreva a **Latitude**, a **Longitude** e a **Direção (graus)**. A direção é o sentido em que os corredores atravessam, no sentido dos ponteiros do relógio a partir do norte: 0 é norte, 90 este, 180 sul e 270 oeste.',
						'Defina o **Alcance de cada lado**, de 5 a 100 m. Torne-o largo o suficiente para cobrir toda a estrada ou caminho, e um pouco mais.',
						'Escolha **Guardar linha**.',
					],
				},
				{
					type: 'p',
					text: 'Cada linha é guardada por si só, de imediato; não precisa de guardar o evento. Uma linha que moveu mostra **Colocada por um organizador**. Escolha **Repor a partir da rota** para a voltar a pôr onde a rota a coloca.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Uma linha que colocou fica exatamente onde a pôs, mesmo que altere depois a rota do percurso. Depois de alterar uma rota, verifique os avisos por baixo de cada linha.',
				},
			],
		},
		{
			heading: 'Avisos no editor',
			blocks: [
				{
					type: 'list',
					items: [
						'A linha está a mais de 100 m da rota do percurso. Verifique se está no sítio certo.',
						'A linha aponta contra o sentido da rota, por isso quem segue a rota atravessá-la-ia ao contrário. Inverta o sentido da linha.',
						'A rota atravessa a sua própria linha de chegada antes do fim, como acontece num percurso de voltas ou numa pista. A chegada pela linha fica então desligada nesse percurso, e os corredores terminam premindo Parar ou Concluir.',
					],
				},
			],
		},
		{
			heading: 'Percursos sem rota',
			blocks: [
				{
					type: 'p',
					text: 'Um percurso sem rota não tem linhas até as colocar. Escolha **Colocar linha de partida** ou **Colocar linha de chegada**. Se já tiver movido o mapa para o local, a linha começa no centro do mapa; caso contrário, escreva a sua posição. Depois defina a direção e o alcance e escolha **Guardar linha**. **Remover linha** volta a retirar uma linha que colocou.',
				},
			],
		},
		{
			heading: 'As linhas ficam fixas quando a prova começa',
			blocks: [
				{
					type: 'p',
					text: 'Quando prepara uma prova (numa prova de tempo próprio, quando a janela abre), as linhas de cada percurso são copiadas para essa prova. Todos os corredores atravessam então as mesmas linhas, mude o que mudar durante a prova. Uma alteração que faça depois aplica-se a partir da próxima prova. A página do evento e a página da prova em direto mostram as linhas com que a prova foi preparada.',
				},
			],
		},
		{
			heading: 'Verificações antes de uma prova',
			blocks: [
				{
					type: 'p',
					text: 'Antes de uma prova ser preparada, as linhas de todos os percursos são verificadas, na web e na app do telemóvel. Um aviso permite-lhe **Preparar na mesma**; um problema marcado com **Tem de corrigir:** impede que a prova seja preparada até o corrigir no editor do evento, na web.',
				},
				{
					type: 'list',
					items: [
						'Um percurso sem linha de chegada e sem ponto de chegada: um aviso, porque os seus corredores terminam manualmente. Numa prova de tempo próprio, tem de ser corrigido.',
						'Um percurso sem linha de partida: numa prova de tempo próprio, tem de ser corrigido. As outras provas podem começar sem ela.',
						'Uma rota que atravessa a sua própria linha de chegada antes do fim: um aviso, porque a chegada pela linha fica desligada nesse percurso. Numa prova de tempo próprio, tem de ser corrigido.',
						'Uma linha a mais de 100 m da rota: um aviso em qualquer tipo de prova.',
					],
				},
				{
					type: 'p',
					text: 'O tipo de prova que está a organizar define-se em **Como a corrida começa**; consulte [[guide:choose-how-your-race-starts|Escolher como começa a sua prova]].',
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
