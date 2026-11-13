import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'racing-in-a-race',
	title: 'Competir en una carrera en directo',
	summary: 'Apúntate, elige tu recorrido, empieza a grabar antes de la línea de salida y deja que tu móvil o tu reloj te cronometre desde la línea de salida hasta la línea de meta.',
	sections: [
		{
			heading: 'Con qué dispositivos se puede competir',
			blocks: [
				{
					type: 'list',
					items: [
						'App de Android: compatibilidad completa. Muestra el aviso de carrera, envía tu posición en directo y te cronometra por las líneas de salida y de meta.',
						'App de iPhone: usa el mismo código que la de Android, pero todavía no se ha probado en un iPhone en una carrera real.',
						'Reloj Wear OS: compatibilidad completa en la muñeca, incluido el cronometraje por las líneas. Aun así, te apuntas y eliges tu recorrido en la web o en el móvil.',
						'Apple Watch: solo compatibilidad inicial. Muestra el aviso de carrera, envía tu posición y comunica tu tiempo a través de tu iPhone, pero no detecta las líneas de salida y de meta, así que no tiene llegada automática, y no se ha probado en una carrera real. Lleva el móvil como respaldo, o vuelve a cronometrar tu resultado con tu traza en la web después.',
						'Web: úsala para apuntarte, elegir un recorrido, ver los resultados y volver a cronometrar un resultado con la traza de una actividad. Un navegador no puede grabar una actividad.',
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
						'Si hay más de un recorrido, elige el tuyo en **Tu recorrido** en la web. En la app del móvil se te pide **Elige tu recorrido** cuando tocas **Me apunto**.',
						'Toca **Me apunto**. Solo una inscripción con **Me apunto** recibe los avisos de carrera en tu dispositivo; **Quizás** no.',
					],
				},
				{
					type: 'p',
					text: '¿Has cambiado de idea? En la web, elige otro recorrido en **Tu recorrido** (verás «Recorrido actualizado.»). En la app del móvil, toca **Cambiar recorrido**. Decide tu recorrido antes de empezar a grabar: tu móvil o tu reloj lo lee cuando empieza la grabación de tu carrera, y tu resultado va al panel de ese recorrido.',
				},
			],
		},
		{
			heading: 'Carrera preparada y Carrera EN VIVO',
			blocks: [
				{
					type: 'p',
					text: 'Cuando el organizador prepara la carrera, la pestaña Correr de la app del móvil muestra **Carrera preparada** con «esperando el GO». El reloj Wear OS muestra «CARRERA PREPARADA» encima de su botón Empezar. Cuando el organizador da el GO, cambia a **Carrera EN VIVO** («CARRERA EN VIVO» en el reloj) con el tiempo transcurrido y «toca Iniciar».',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Tu móvil o tu reloj no empieza a grabar por sí solo: pulsa Iniciar tú mismo, antes de llegar a la línea de salida. Puedes empezar mientras la carrera muestra **Carrera preparada**, o cuando veas **Carrera EN VIVO**. Una grabación iniciada antes de tiempo se une a la carrera en el GO, en el móvil y en un reloj Wear OS.',
				},
				{
					type: 'p',
					text: 'La app del móvil busca las carreras en las que dijiste **Me apunto** que empiezan en el próximo día. Si el aviso tarda en aparecer, deja la app abierta en la pestaña Correr durante un minuto.',
				},
			],
		},
		{
			heading: 'Cruzar la línea de salida',
			blocks: [
				{
					type: 'p',
					text: 'Cuando tu recorrido tiene línea de salida, la pantalla Correr muestra a qué distancia está, por ejemplo «120 m hasta la línea de salida». Crúzala en el sentido del recorrido. Después del GO, tu móvil o tu reloj Wear OS vibra, dice «Línea de salida cruzada, cronometrando» si tienes activados los avisos de voz, y tu tiempo chip empieza a contar desde ese momento.',
				},
				{
					type: 'list',
					items: [
						'¿Ya habías pasado la línea de salida cuando suena el GO? Tu salida es el propio GO.',
						'Cruzar la línea antes del GO, por ejemplo mientras calientas, no cuenta. Después del GO, tu salida cuenta cuando llevas unos 50 m de recorrido sin volver a cruzar la línea.',
						'Si tu móvil o tu reloj nunca detecta que cruzas la línea de salida, tu tiempo chip cuenta desde que pulsaste Iniciar.',
					],
				},
			],
		},
		{
			heading: 'Llegada automática',
			blocks: [
				{
					type: 'p',
					text: 'No tienes que pulsar nada en la meta. Cuando tu recorrido tiene línea de meta, tu móvil o tu reloj Wear OS registra tu llegada en el momento en que la cruzas en el sentido del recorrido, siempre que hayas cubierto lo suficiente: el 60 % de su distancia desde que cruzaste la línea de salida, o el 90 % si no se detectó ese cruce. Así, un recorrido circular, que empieza donde termina, no te da por llegado nada más salir.',
				},
				{
					type: 'p',
					text: 'Pasar junto a la línea de meta por un camino paralelo no cuenta, porque no llegas a cruzarla. Tu tiempo se toma en el momento en que cruzaste la línea. El móvil vibra y muestra «¡Meta!» con tu tiempo bruto.',
				},
				{
					type: 'p',
					text: 'Un recorrido con punto de meta pero sin línea de meta mantiene la regla anterior: llegas cuando estás a menos de 30 m de la meta y has cubierto el 90 % del recorrido, cronometrado en el momento en que estuviste más cerca. En un recorrido con línea de meta, ese círculo de 30 m solo cuenta si pulsas Detener o **Terminar carrera** dentro de él.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'No hay llegada automática si tu recorrido no tiene distancia, no tiene ni línea ni punto de meta, o tiene una ruta que cruza su propia línea de meta antes del final, como un recorrido de vueltas. Usa Detener y luego **Terminar carrera** cuando cruces la línea.',
				},
			],
		},
		{
			heading: '¿No has terminado? Reanudar',
			blocks: [
				{
					type: 'p',
					text: 'Una llegada por la línea se envía al instante y tu grabación se pausa. Durante los 60 segundos siguientes, la pantalla Correr ofrece **¿No has terminado? Reanudar**, en el móvil y en un reloj Wear OS. Si no has terminado, por ejemplo porque cruzaste la línea antes de tiempo en una vuelta, tócalo: tu resultado se retira y la grabación continúa. Si no haces nada, la grabación se detiene y el resultado se mantiene.',
				},
				{
					type: 'p',
					text: 'Después de anular una llegada, termina el resto de la carrera a mano: toca Detener y luego **Terminar carrera** cuando termines de verdad. Si la app se reinicia antes, vuelve a vigilar la línea de meta, pero nunca cuenta la llegada que anulaste.',
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
			heading: 'Tiempo bruto, tiempo chip y salidas tardías',
			blocks: [
				{
					type: 'list',
					items: [
						'El **Tiempo bruto** va desde el momento en que el organizador dio el GO hasta tu llegada. Es el tiempo por el que se te clasifica.',
						'El **Tiempo chip** va desde que cruzas la línea de salida hasta tu llegada. Si no se detectó ese cruce, cuenta desde que pulsaste Iniciar, o desde el GO si pulsaste Iniciar antes. Nunca es más largo que tu tiempo bruto.',
						'Si empiezas más de 5 minutos después del GO, o tu primera posición está a más de 200 m del inicio del recorrido, la app del móvil muestra un aviso de salida tardía y un reloj Wear OS mantiene **Salida tardía** bajo el reloj de carrera. Tu tiempo bruto sigue contando desde el GO, así que una salida tardía lo hace más largo que tu tiempo chip.',
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
					text: 'Si el organizador finaliza la carrera antes de que llegues, tu móvil te lo indica y tu reloj muestra «Carrera finalizada». Tu actividad sigue grabándose como cualquier otra, pero tu dispositivo no envía ningún resultado a la carrera. Si ya habías enviado una posición en directo, la carrera te marca como DNF.',
				},
			],
		},
	],
	sources: {
		title: '3ce73ee9613bf595',
		summary: '8a84191c960f3189',
		's0.heading': 'ac0fdba8f9fafc40',
		's0.b0.i0': '5f9d1c45bcbbfb31',
		's0.b0.i1': 'c4096345432d33e6',
		's0.b0.i2': '547cdcc69e247581',
		's0.b0.i3': 'f068efe69456ba52',
		's0.b0.i4': '13822228d183e2b0',
		's1.heading': 'f00c55d7857a6dce',
		's1.b0.i0': '30eeadd878d7b098',
		's1.b0.i1': '525a552fd753b987',
		's1.b0.i2': '9efc1bb52d90e6ef',
		's1.b1': '55c32b3a7d7a241c',
		's2.heading': 'ed31d49e898938c8',
		's2.b0': 'f4ff1ecc36a2cf8e',
		's2.b1': 'b77e8bc9d60c9032',
		's2.b2': 'ddeff25fbc81b659',
		's3.heading': '3a0b0b0d9f43041c',
		's3.b0': '521195c2168d7fda',
		's3.b1.i0': '90b0261b0ce9c3f1',
		's3.b1.i1': 'a8d5dd7d6540cf62',
		's3.b1.i2': '8984cdb2a3694851',
		's4.heading': 'b1c0468dde456524',
		's4.b0': '900f305519a8032c',
		's4.b1': '32f9e651e83644d2',
		's4.b2': 'b39f1ce0d4a09d1a',
		's4.b3': '0e408636f1230c3b',
		's5.heading': 'bfa00064941be0cc',
		's5.b0': '86c65402c413b22d',
		's5.b1': 'a71d2963bd840180',
		's6.heading': '5df934589d491767',
		's6.b0': 'f1a6d8c09124a7d8',
		's6.b1.i0': '7a35b26309af9c5b',
		's6.b1.i1': 'f2cbc2dc9b04ff5b',
		's6.b1.i2': '630eba7ef0538b75',
		's6.b2': 'a0e378aecf393dda',
		's6.b3': 'b99b4c432279d3ea',
		's7.heading': '19cee1ff0ce4a9e3',
		's7.b0': 'b44459cc78b71aaf',
		's8.heading': 'b26ffa9d3d25af83',
		's8.b0.i0': '5aa5f4e57b72adfb',
		's8.b0.i1': '43b664e01ad5869b',
		's8.b0.i2': 'ce8974750a19dc0f',
		's8.b1': '1a0778a6029af8ae',
		's9.heading': '8cfcf517e30f6408',
		's9.b0': 'e103d457341fcf30',
	},
};
