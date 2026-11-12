import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'how-segment-times-are-measured',
	title: 'Cómo se miden los tiempos de segmento',
	summary: 'Los tiempos de segmento y de recorrido de parque van de una línea de salida a una línea final, cruzadas en el sentido correcto, y cuenta tu paso más rápido.',
	sections: [
		{
			heading: 'Líneas de salida y final',
			blocks: [
				{
					type: 'p',
					text: 'Cada segmento tiene una línea de salida y una línea final, una atravesando el camino en cada extremo, mirando en el sentido del segmento y extendiéndose 15 m a cada lado. Un recorrido de parque también es un segmento, así que se cronometra igual.',
				},
				{
					type: 'list',
					items: [
						'Tu tiempo cuenta desde el momento en que tu carrera cruza la línea de salida hasta el momento en que cruza la línea final.',
						'Cada cruce se calcula entre los dos puntos GPS situados a ambos lados de la línea, en lugar de tomarse en el punto que quedara más cerca, así que el tiempo se acerca más al real.',
						'Las dos líneas deben cruzarse en el sentido del segmento. Cruzar una al revés no cuenta.',
						'La distancia que recorres entre los dos cruces no debe diferir en más de un 25 % de la longitud del segmento y, en un recorrido de parque, debes pasar por todos los puntos de control, en orden, entre ambos cruces.',
					],
				},
			],
		},
		{
			heading: 'Por qué no cuenta un camino paralelo',
			blocks: [
				{
					type: 'p',
					text: 'Una carrera por un camino paralelo al segmento, a 20 m, se acerca a los dos extremos sin pasar nunca a través de las líneas, así que no obtiene tiempo. Tampoco la ida de una ruta de ida y vuelta que solo pasa cerca del final.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Empieza a grabar un poco antes de la línea de salida. Una carrera cuya grabación empieza en la línea, o después de ella, nunca la cruza y no obtiene tiempo en ese segmento.',
				},
			],
		},
		{
			heading: 'Más de un paso',
			blocks: [
				{
					type: 'list',
					items: [
						'Si tu carrera pasa por el segmento más de una vez, cuenta tu paso más rápido.',
						'Un calentamiento que vuelve a pasar por la línea de salida no alarga tu tiempo: el tiempo empieza en tu último cruce de la línea de salida antes del final.',
						'En un circuito se cronometra cada vuelta completa y cuenta tu vuelta más rápida. Cuando la salida y el final son la misma línea, el cruce que cierra una vuelta abre también la siguiente.',
					],
				},
			],
		},
		{
			heading: 'Segmentos sin líneas',
			blocks: [
				{
					type: 'p',
					text: 'Un segmento demasiado corto en uno de sus extremos para colocar ahí una línea no tiene líneas. Se sigue cronometrando a la manera antigua: tu carrera debe pasar a menos de 35 m de su inicio y después a menos de 35 m de su final.',
				},
			],
		},
		{
			heading: 'Esfuerzos anteriores',
			blocks: [
				{
					type: 'p',
					text: 'Los esfuerzos grabados antes de que los segmentos tuvieran líneas se midieron a la manera antigua, pasando cerca del inicio y del final. Cada uno se vuelve a medir con las líneas la próxima vez que su corredor abre la carrera en la web. Su tiempo puede cambiar, y puede desaparecer si la carrera nunca cruzó las líneas.',
				},
				{
					type: 'p',
					text: 'Hasta que todos los esfuerzos de un segmento se hayan vuelto a medir, su clasificación indica que algunos esfuerzos anteriores se midieron a la manera antigua.',
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
