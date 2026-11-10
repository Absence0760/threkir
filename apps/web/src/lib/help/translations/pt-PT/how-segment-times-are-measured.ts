import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'how-segment-times-are-measured',
	title: 'Como são medidos os tempos dos segmentos',
	summary: 'Os tempos dos segmentos e dos percursos de parque contam de uma linha de partida a uma linha de fim, atravessadas no sentido certo, e conta a sua passagem mais rápida.',
	sections: [
		{
			heading: 'Linhas de partida e de fim',
			blocks: [
				{
					type: 'p',
					text: 'Cada segmento tem uma linha de partida e uma linha de fim, uma a atravessar o caminho em cada extremidade, virada no sentido do segmento e com um alcance de 15 m para cada lado. Um percurso de parque também é um segmento, por isso é cronometrado da mesma forma.',
				},
				{
					type: 'list',
					items: [
						'O seu tempo conta desde o momento em que a sua corrida atravessa a linha de partida até ao momento em que atravessa a linha de fim.',
						'Cada passagem é calculada entre os dois pontos GPS de cada lado da linha, e não no ponto que por acaso ficou mais perto, por isso o tempo fica mais próximo do real.',
						'As duas linhas têm de ser atravessadas no sentido do segmento. Atravessar uma ao contrário não conta.',
						'A distância que percorreu entre as duas passagens não pode diferir mais de 25% do comprimento do segmento e, num percurso de parque, tem de passar por todos os pontos de controlo, pela ordem, entre elas.',
					],
				},
			],
		},
		{
			heading: 'Porque é que um caminho paralelo não conta',
			blocks: [
				{
					type: 'p',
					text: 'Uma corrida num caminho paralelo ao segmento, a 20 m de distância, passa perto das duas extremidades sem nunca atravessar as linhas, por isso não recebe tempo. O mesmo acontece com a ida de uma rota de ida e volta que só passa perto do fim.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Comece a gravar um pouco antes da linha de partida. Uma corrida cuja gravação começa em cima da linha, ou depois dela, nunca a atravessa e não recebe tempo nesse segmento.',
				},
			],
		},
		{
			heading: 'Mais do que uma passagem',
			blocks: [
				{
					type: 'list',
					items: [
						'Se a sua corrida passar pelo segmento mais do que uma vez, conta a sua passagem mais rápida.',
						'Um aquecimento que volta a passar pela linha de partida não aumenta o seu tempo: o tempo começa na sua última passagem pela linha de partida antes do fim.',
						'Num circuito cuja partida e fim são a mesma linha, a passagem que termina uma volta não pode também iniciar a seguinte. Por isso, só é cronometrada uma volta sim, outra não (a primeira, a terceira e assim por diante), e conta a mais rápida dessas. Um circuito que começa e acaba em linhas diferentes cronometra todas as voltas.',
					],
				},
			],
		},
		{
			heading: 'Segmentos sem linhas',
			blocks: [
				{
					type: 'p',
					text: 'Um segmento demasiado curto numa das extremidades para lá colocar uma linha não tem linhas. Continua a ser cronometrado da forma antiga: a sua corrida tem de passar a menos de 35 m da partida e depois a menos de 35 m do fim.',
				},
			],
		},
		{
			heading: 'Tentativas mais antigas',
			blocks: [
				{
					type: 'p',
					text: 'As tentativas gravadas antes de os segmentos terem linhas foram medidas da forma antiga, passando perto da partida e do fim. Cada uma é medida de novo pelas linhas da próxima vez que o respetivo corredor abrir a corrida no site. O tempo pode mudar, e a tentativa pode desaparecer se a corrida nunca tiver atravessado as linhas.',
				},
				{
					type: 'p',
					text: 'Até todas as tentativas de um segmento terem sido medidas de novo, a respetiva classificação indica que algumas tentativas mais antigas foram medidas da forma antiga.',
				},
			],
		},
	],
	sources: {
		title: 'af6ac26d6646f774',
		summary: 'a18775a50f19720a',
		's0.heading': 'e4b2458df12fdaf3',
		's0.b0': 'cd68d1e94a0f5ab9',
		's0.b1.i0': '6f3bd850e275ed2a',
		's0.b1.i1': '1f53338704ded34d',
		's0.b1.i2': 'bbbd3c6ebb557922',
		's0.b1.i3': '6b8289f9cfe75cdc',
		's1.heading': 'a7fcd26c4192d17b',
		's1.b0': '433e0989f5c0bcdb',
		's1.b1': '762d24e1e2186155',
		's2.heading': '07aa1107fe80687c',
		's2.b0.i0': 'd1cc20d8bffef410',
		's2.b0.i1': '49b20e543d91d563',
		's2.b0.i2': 'd8dc1f1202af2dc9',
		's3.heading': '6ce1d76024b4fe1f',
		's3.b0': '2f8dce267fbf234c',
		's4.heading': 'f2e748afe43f1604',
		's4.b0': '73985bbd2197a3b7',
		's4.b1': '02549166218656ab',
	},
};
