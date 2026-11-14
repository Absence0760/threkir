import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-results-explained',
	title: 'Los resultados de carrera, explicados',
	summary: 'Qué significan el tiempo bruto y el tiempo chip, cómo se calculan los puestos, qué indican las marcas Manual, Organizador, DNF, DNS y pendiente, y cómo recalcular el tiempo con tu traza.',
	sections: [
		{
			heading: 'Tiempo bruto y tiempo chip',
			blocks: [
				{
					type: 'list',
					items: [
						'El **Tiempo bruto** se mide desde el momento en que el organizador dio el GO hasta el momento en que cruzaste la meta. El GO lo marca nuestro servidor, así que todos los participantes comparten la misma salida.',
						'El **Tiempo chip** se mide desde que cruzaste la línea de salida del recorrido hasta tu llegada. Si tu móvil o tu reloj no detectó ningún cruce de la línea de salida, cuenta desde que pulsaste Iniciar en tu propio dispositivo, incluidas las pausas.',
						'Una carrera con cronometraje propio no tiene GO, así que no tiene tiempo bruto: su panel muestra tu tiempo chip, desde la línea de salida hasta la línea de meta.',
						'El tiempo grande del panel es tu tiempo bruto cuando la carrera tuvo un GO, y si no, tu tiempo chip. Los puestos se calculan a partir de ese tiempo grande.',
					],
				},
				{
					type: 'p',
					text: 'En la web, la línea pequeña bajo un tiempo dice algo como «oficial 41:58 · chip 41:20». En la app del móvil, bajo el tiempo principal aparece un tiempo «chip» cuando es distinto. Si saliste tarde, tu tiempo bruto es más largo que tu tiempo chip.',
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
						'*Sin insignia*: el móvil o el reloj del corredor cronometró la llegada, en el momento en que cruzó la línea de meta o, en un recorrido sin línea de meta, al entrar en el círculo de 30 m alrededor de la meta. Es el caso normal, así que ni la web ni la app del móvil lo marcan.',
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
			heading: 'Recalcular el tiempo con tu traza',
			blocks: [
				{
					type: 'p',
					text: 'Si tu móvil no detectó una línea, tu resultado es un DNF que no esperabas o competiste con un Apple Watch, puedes volver a cronometrar tu resultado con la actividad que grabaste. Abre la actividad en la web: si pertenece a una carrera, muestra **Recalcular el tiempo con mi traza** con tu resultado actual junto al que da tu traza.',
				},
				{
					type: 'steps',
					items: [
						'Revisa las dos columnas: tiempo bruto, tiempo chip y si la salida y la llegada se cronometraron por la línea.',
						'Elige **Recalcular resultado** y luego **Sustituir resultado**.',
					],
				},
				{
					type: 'list',
					items: [
						'Cronometra tu traza por las líneas de salida y de meta con las que se corrió la carrera, con el mismo reloj que usó tu móvil o tu reloj durante la carrera.',
						'Puedes recalcularlo hasta 24 horas después de que termine la carrera. Pasado ese plazo, tu tiempo, tu recorrido y tu distancia quedan bloqueados, y solo el organizador puede cambiar tu tiempo.',
						'Sustituye un DNF, un tiempo terminado a mano y un resultado pendiente de revisión. Nunca sustituye un tiempo que fijó el organizador ni un resultado ya cronometrado por las dos líneas; en una carrera con cronometraje propio, solo lo sustituye un intento más rápido cronometrado por las dos líneas.',
						'Si el organizador aprueba los resultados a mano, un resultado recalculado vuelve a él para que lo apruebe.',
					],
				},
			],
		},
		{
			heading: 'Algo no cuadra',
			blocks: [
				{
					type: 'list',
					items: [
						'¿No aparece ningún resultado? Si tu dispositivo no tenía señal en la meta, envía el resultado cuando se vuelve a conectar, dentro de las 24 horas siguientes al final de la carrera. En esas mismas 24 horas también puedes recalcularlo con tu traza.',
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
