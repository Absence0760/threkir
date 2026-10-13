import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-results-explained',
	title: 'Los resultados de carrera, explicados',
	summary: 'Qué significan el tiempo oficial y el tiempo chip, cómo se calculan los puestos por recorrido y qué indican las marcas Manual, Organizador, DNF, DNS y pendiente.',
	sections: [
		{
			heading: 'Tiempo oficial y tiempo chip',
			blocks: [
				{
					type: 'list',
					items: [
						'El **Tiempo oficial** se mide desde el momento en que el organizador dio la salida hasta el momento en que cruzaste la meta. La salida la marca nuestro servidor, así que todos los participantes comparten la misma salida.',
						'El **Tiempo chip** se mide desde que pulsaste Iniciar en tu propio dispositivo hasta tu llegada, incluidas las pausas.',
						'El tiempo grande del panel es tu tiempo oficial cuando la carrera tuvo salida, y si no, tu tiempo chip. Los puestos se calculan a partir de ese tiempo grande.',
					],
				},
				{
					type: 'p',
					text: 'En la web, la línea pequeña bajo un tiempo dice algo como «oficial 41:58 · chip 41:20». En la app del móvil, bajo el tiempo principal aparece un tiempo «chip» cuando es distinto. Si saliste tarde, tu tiempo oficial es más largo que tu tiempo chip.',
				},
			],
		},
		{
			heading: 'Los puestos son por recorrido',
			blocks: [
				{
					type: 'p',
					text: 'Cuando una carrera tiene más de un recorrido, cada recorrido tiene su propio panel y sus propios puestos. Quien termina un 5K nunca se clasifica contra quien termina un 10K. Los resultados sin recorrido se agrupan juntos (**Sin recorrido** en la página del evento, **Otros** en la página en directo).',
				},
				{
					type: 'p',
					text: 'Solo quienes terminan obtienen puesto. Los empates se deshacen a favor del resultado que llegó primero.',
				},
			],
		},
		{
			heading: 'Cómo se registró la llegada',
			blocks: [
				{
					type: 'list',
					items: [
						'**Sin insignia**: el móvil o el reloj del corredor detectó la línea de meta. Es el caso normal, así que ni la web ni la app del móvil lo marcan.',
						'**Manual**: el corredor terminó a mano, ya sea con **Terminar carrera** tras cubrir al menos el 90 % del recorrido o con **Enviar mi tiempo** en la web durante la carrera.',
						'**Organizador** (en la web, **Editado por el organizador**): el organizador introdujo o corrigió este resultado, o el corredor quedó marcado como DNF al finalizar el organizador la carrera.',
					],
				},
			],
		},
		{
			heading: 'DNF y DNS',
			blocks: [
				{
					type: 'list',
					items: [
						'**DNF** (no terminó): el corredor tomó la salida pero no terminó. Ocurre cuando alguien elige **Terminar como DNF** antes de cubrir el 90 % del recorrido, cuando el organizador finaliza la carrera mientras sigue en ella, o cuando el organizador lo registra.',
						'**DNS** (no tomó la salida): lo registra el propio corredor con **Registrar DNS** o el organizador.',
						'Ninguno de los dos obtiene puesto. En la página en directo aparecen en **No finalizó**.',
					],
				},
			],
		},
		{
			heading: 'Resultados pendientes',
			blocks: [
				{
					type: 'p',
					text: 'Si el organizador desactivó la aprobación automática, cada resultado nuevo espera al organizador. En la página del evento en la web muestra **PENDIENTE** todavía sin puesto; en la app del móvil y en la página en directo muestra **Pendiente**. En cuanto el organizador elige **Aprobar**, ocupa su puesto en el panel.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'El **Certificado** de llegada solo se puede descargar cuando se ha aprobado un resultado de llegada.',
				},
			],
		},
		{
			heading: 'Algo no cuadra',
			blocks: [
				{
					type: 'list',
					items: [
						'¿No aparece ningún resultado? Si tu dispositivo no tenía señal en la meta, envía el resultado cuando se vuelve a conectar, dentro de las 24 horas siguientes al final de la carrera.',
						'¿Un DNF que crees que es un error, o un tiempo que no cuadra? Pregunta al organizador. Puede corregirlo en la web, y entonces el resultado mostrará la marca del organizador.',
					],
				},
				{
					type: 'p',
					text: 'Para la parte de los corredores, consulta [[guide:racing-in-a-race|Competir en una carrera en directo]]. Organizadores: [[guide:race-day-for-hosts|El día de la carrera para organizadores]].',
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
