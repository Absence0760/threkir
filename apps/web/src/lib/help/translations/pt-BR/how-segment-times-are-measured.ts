import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'how-segment-times-are-measured',
	title: 'Como os tempos de segmento são medidos',
	summary: 'Os tempos de segmentos e de percursos de parques vão de uma linha de largada até uma linha final, cruzadas no sentido certo, e vale a sua passagem mais rápida.',
	sections: [
		{
			heading: 'Linha de largada e linha final',
			blocks: [
				{
					type: 'p',
					text: 'Cada segmento tem uma linha de largada e uma linha final, uma atravessando o caminho em cada ponta, voltadas para o sentido do segmento e com alcance de 15 m para cada lado. Um percurso de parque também é um segmento, então é cronometrado da mesma forma.',
				},
				{
					type: 'list',
					items: [
						'Seu tempo vai do momento em que a sua corrida cruza a linha de largada até o momento em que ela cruza a linha final.',
						'Cada cruzamento é calculado entre os dois pontos de GPS de cada lado da linha, e não tomado no ponto que por acaso estava mais perto, então o tempo fica mais próximo do real.',
						'As duas linhas precisam ser cruzadas no sentido do segmento. Cruzar uma delas ao contrário não conta.',
						'A distância que você percorreu entre os dois cruzamentos não pode diferir em mais de 25% do comprimento do segmento e, em um percurso de parque, você precisa passar por todos os pontos de controle, em ordem, no meio do caminho.',
					],
				},
			],
		},
		{
			heading: 'Por que um caminho paralelo não conta',
			blocks: [
				{
					type: 'p',
					text: 'Uma corrida em um caminho paralelo ao segmento, a 20 m dele, chega perto das duas pontas sem nunca passar pelas linhas, então não recebe tempo. O mesmo vale para a ida de uma rota de ida e volta que só passa perto do fim.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Comece a gravar um pouco antes da linha de largada. Uma corrida cuja gravação começa em cima da linha, ou depois dela, nunca a cruza e não recebe tempo nesse segmento.',
				},
			],
		},
		{
			heading: 'Mais de uma passagem',
			blocks: [
				{
					type: 'list',
					items: [
						'Se a sua corrida passar pelo segmento mais de uma vez, vale a sua passagem mais rápida.',
						'Um aquecimento que volta e cruza de novo a linha de largada não aumenta o seu tempo: o tempo começa no seu último cruzamento da linha de largada antes do fim.',
						'Em um circuito, cada volta completa é cronometrada e vale a sua volta mais rápida. Quando o início e o fim são a mesma linha, o cruzamento que encerra uma volta também inicia a seguinte.',
					],
				},
			],
		},
		{
			heading: 'Segmentos sem linhas',
			blocks: [
				{
					type: 'p',
					text: 'Um segmento curto demais em uma das pontas para receber uma linha ali não tem linhas. Ele continua sendo cronometrado do jeito antigo: sua corrida precisa passar a menos de 35 m do início dele e depois a menos de 35 m do fim.',
				},
			],
		},
		{
			heading: 'Tentativas mais antigas',
			blocks: [
				{
					type: 'p',
					text: 'As tentativas registradas antes de os segmentos terem linhas foram medidas do jeito antigo, passando perto do início e do fim. Cada uma é medida de novo pelas linhas na próxima vez que o corredor abrir a corrida no site. O tempo pode mudar, e a tentativa pode sumir se a corrida nunca cruzou as linhas.',
				},
				{
					type: 'p',
					text: 'Até que todas as tentativas de um segmento tenham sido medidas de novo, a classificação dele avisa que algumas tentativas mais antigas foram medidas do jeito antigo.',
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
		's2.b0.i2': '768a4bc2c007e9bb',
		's3.heading': '6ce1d76024b4fe1f',
		's3.b0': '2f8dce267fbf234c',
		's4.heading': 'f2e748afe43f1604',
		's4.b0': '73985bbd2197a3b7',
		's4.b1': '02549166218656ab',
	},
};
