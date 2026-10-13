import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'racing-in-a-race',
	source: '92b29a6c8a21703a',
	title: 'Competir en una carrera en directo',
	summary: 'Apúntate, elige tu recorrido, empieza a grabar en la línea de salida o después de la salida y deja que tu móvil o tu reloj te cronometre al cruzar la meta.',
	sections: [
		{
			heading: 'Con qué dispositivos se puede competir',
			blocks: [
				{
					type: 'list',
					items: [
						'App de Android: compatibilidad completa. Muestra el aviso de carrera, envía tu posición en directo y registra tu llegada automáticamente.',
						'App de iPhone: usa el mismo código que la de Android, pero todavía no se ha probado en un iPhone en una carrera real.',
						'Reloj Wear OS: compatibilidad completa en la muñeca, incluida la llegada automática. Aun así, te apuntas y eliges tu recorrido en la web o en el móvil.',
						'Apple Watch: solo compatibilidad inicial. Muestra el aviso de carrera, envía tu posición y comunica tu tiempo a través de tu iPhone, pero no tiene llegada automática y no se ha probado en una carrera real. Lleva el móvil como respaldo.',
						'Web: úsala para apuntarte, elegir un recorrido y ver los resultados. Un navegador no puede grabar una carrera.',
					],
				},
			],
		},
		{
			heading: 'Apuntarse y elegir un recorrido',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre el evento de la carrera.',
						'Si hay más de un recorrido, elige el tuyo en **Tu recorrido** en la web. En la app del móvil se te pide **Elige tu recorrido** cuando tocas **Voy**.',
						'Toca **Voy**. Solo una inscripción con **Voy** recibe los avisos de carrera en tu dispositivo; **Quizás** no.',
					],
				},
				{
					type: 'p',
					text: '¿Has cambiado de idea? En la web, elige otro recorrido en **Tu recorrido** (verás «Recorrido actualizado.»). En la app del móvil, toca **Cambiar recorrido**. Decide tu recorrido antes de empezar a grabar: tu móvil o tu reloj lo lee cuando empieza la grabación de tu carrera, y tu resultado va al panel de ese recorrido.',
				},
			],
		},
		{
			heading: 'Carrera lista y Carrera EN VIVO',
			blocks: [
				{
					type: 'p',
					text: 'Cuando el organizador prepara la carrera, la pestaña Correr de la app del móvil muestra **Carrera lista** con «esperando la salida». El reloj Wear OS muestra «CARRERA LISTA» encima de su botón Empezar. Cuando el organizador da la salida, cambia a **Carrera EN VIVO** («CARRERA EN VIVO» en el reloj) con el tiempo transcurrido y «toca Iniciar».',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Tu móvil o tu reloj no empieza a grabar por sí solo: pulsa Iniciar tú mismo. Puedes empezar en la línea de salida mientras la carrera muestra **Carrera lista**, o cuando veas **Carrera EN VIVO**. Una grabación iniciada antes de tiempo se une a la carrera en la salida, en el móvil y en un reloj Wear OS, y tu tiempo chip cuenta entonces desde la salida y no desde que pulsaste Iniciar.',
				},
				{
					type: 'p',
					text: 'La app del móvil busca las carreras en las que dijiste **Voy** que empiezan en el próximo día. Si el aviso tarda en aparecer, deja la app abierta en la pestaña Correr durante un minuto.',
				},
			],
		},
		{
			heading: 'Llegada automática',
			blocks: [
				{
					type: 'p',
					text: 'No tienes que pulsar nada en la meta. Tu móvil o tu reloj Wear OS registra tu llegada cuando se cumplen estas dos condiciones:',
				},
				{
					type: 'list',
					items: [
						'estás a menos de 30 m de la línea de meta, y',
						'has cubierto al menos el 90 % de la distancia de tu recorrido.',
					],
				},
				{
					type: 'p',
					text: 'Tu tiempo se toma en el momento en que estuviste más cerca de la meta, no en el primer momento en que entraste en los 30 m. La regla del 90 % evita que un recorrido circular, que empieza donde termina, te dé por llegado en el primer segundo. El móvil muestra «¡Meta!» con tu tiempo oficial, y tu grabación se detiene.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si tu recorrido no tiene ruta o no tiene distancia, no hay llegada automática. Usa Detener y luego **Terminar carrera** cuando cruces la línea.',
				},
			],
		},
		{
			heading: 'Detenerse durante la carrera',
			blocks: [
				{
					type: 'p',
					text: 'Durante una carrera en directo, Detener no termina tu carrera. Pausa tu grabación y muestra **Carrera en pausa**. El reloj de la carrera sigue corriendo.',
				},
				{
					type: 'list',
					items: [
						'**Reanudar carrera** continúa la grabación.',
						'**Terminar carrera** termina tu carrera ahora. Si has cubierto al menos el 90 % del recorrido, es una llegada manual en ese momento.',
						'Por debajo del 90 %, el botón dice **Terminar como DNF**, y terminar registra un DNF.',
					],
				},
				{
					type: 'p',
					text: 'En un reloj Wear OS, la pantalla de pausa ofrece «Ya» para reanudar, y para terminar mantienes pulsado **Meta**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Terminar antes del 90 % del recorrido registra un DNF. Si solo te paraste a atarte un cordón, elige **Reanudar carrera**.',
				},
			],
		},
		{
			heading: 'Sin señal en la meta',
			blocks: [
				{
					type: 'p',
					text: 'En las líneas de meta suele haber mala señal. Tu móvil y tu reloj Wear OS guardan primero tu resultado y lo envían en cuanto se vuelven a conectar, así que no se pierde. Tiene que llegarnos dentro de las 24 horas siguientes a que el organizador finalice la carrera. No cierres sesión en la app antes de que se haya enviado.',
				},
			],
		},
		{
			heading: 'Tiempo oficial, tiempo chip y salidas tardías',
			blocks: [
				{
					type: 'list',
					items: [
						'El **Tiempo oficial** va desde el momento en que el organizador dio la salida hasta tu llegada. Es el tiempo por el que se te clasifica.',
						'El **Tiempo chip** va desde que pulsaste Iniciar hasta tu llegada, incluidas las pausas. Si pulsaste Iniciar antes de la salida, cuenta desde la salida, así que nunca es más largo que tu tiempo oficial.',
						'Si empiezas más de 5 minutos después de la salida, o tu primera posición está a más de 200 m del inicio del recorrido, la app del móvil muestra un aviso de salida tardía. Tu tiempo oficial sigue contando desde la salida, así que una salida tardía lo hace más largo que tu tiempo chip.',
					],
				},
				{
					type: 'p',
					text: 'Más sobre cómo leer el panel en [[guide:race-results-explained|Los resultados de carrera, explicados]].',
				},
			],
		},
		{
			heading: 'Si el organizador finaliza la carrera antes',
			blocks: [
				{
					type: 'p',
					text: 'Si el organizador finaliza la carrera antes de que llegues, tu móvil te lo indica y tu reloj muestra «Carrera terminada». Tu carrera sigue grabándose como una carrera normal, pero tu dispositivo no envía ningún resultado de competición. Si ya habías enviado una posición en directo, la carrera te marca como DNF.',
				},
			],
		},
	],
};
