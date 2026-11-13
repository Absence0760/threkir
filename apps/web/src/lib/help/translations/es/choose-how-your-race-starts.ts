import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'choose-how-your-race-starts',
	title: 'Elegir cómo empieza tu carrera',
	summary: 'GO del organizador, GO programado o Ventana de cronometraje propio: cuándo usar cada uno, qué haces el día de la carrera y cómo se aprueban los resultados.',
	sections: [
		{
			heading: 'Tres formas de dar la salida',
			blocks: [
				{
					type: 'list',
					items: [
						'**GO del organizador**: preparas la carrera y pulsas GO en la línea. Úsalo cuando estés en la salida con todos, para una salida en masa.',
						'**GO programado**: la carrera empieza sola a la hora que fijes. Úsalo cuando la hora de salida sea fija pero quizá no estés en la línea, o quieras correr tú también. Hasta entonces puedes retrasarla o cancelarla.',
						'**Ventana de cronometraje propio**: no hay salida común. Cada corredor cronometra su propio intento entre la línea de salida y la línea de meta, en cualquier momento mientras la ventana esté abierta. Úsala para una contrarreloj semanal o para un recorrido que la gente corre cuando puede. No hay tiempo de pistola.',
					],
				},
				{
					type: 'p',
					text: 'Se elige en **Cómo empieza la carrera**, en el editor del evento en la web, para un evento de salida en grupo o de ciclismo. La app del móvil puede dirigir la carrera el día (prepararla antes, retrasarla, ampliarla o finalizarla), pero la forma de salida se elige en la web.',
				},
			],
		},
		{
			heading: 'Fijar los horarios',
			blocks: [
				{
					type: 'list',
					items: [
						'GO programado: fija la **Hora de salida** y el **Día de salida** (el mismo día, el día anterior o el día posterior al evento). En **Termina después de, días** y **Horas**, indica cuánto tiempo después del GO termina la carrera sola, salvo que la finalices antes.',
						'Ventana de cronometraje propio: fija **La ventana abre a las** y **Abre el** (desde el día anterior al evento hasta una semana después) y cuánto tiempo permanece abierta en **Duración de la ventana, días** y **Horas**, de 1 minuto a 7 días.',
					],
				},
				{
					type: 'p',
					text: 'Los horarios se escriben y se ven en el reloj del propio evento, en su zona horaria. En la página del evento, el panel de carrera muestra esa zona horaria y, cuando la tuya es distinta, tu propia hora al lado.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Los horarios se guardan relativos a cada ocurrencia del evento. Si mueves el evento, o una de sus ocurrencias, sus horarios de carrera se mueven con él. Si cambias los horarios en el editor, todas las ocurrencias que aún no han empezado toman los nuevos horarios.',
				},
			],
		},
		{
			heading: 'El día de la carrera: GO del organizador',
			blocks: [
				{
					type: 'p',
					text: 'Preparas la carrera, das el GO y la finalizas tú mismo. Consulta [[guide:race-day-for-hosts|El día de la carrera para organizadores]].',
				},
			],
		},
		{
			heading: 'El día de la carrera: GO programado',
			blocks: [
				{
					type: 'list',
					items: [
						'No tienes que hacer nada. La carrera se configura aproximadamente un día antes de la salida y empieza sola a la hora programada.',
						'Para revisar antes las líneas del recorrido, elige **Preparar antes**.',
						'Antes de la salida, el panel de carrera muestra **Salida a las** con la hora y una cuenta atrás. Para retrasar la salida, introduce los minutos y elige **Retrasar salida**; se avisa a todos los apuntados de que la salida ha cambiado. Elige **Cancelar** para suspender la carrera.',
						'Una vez pasada la hora de salida, la carrera ya no se puede cancelar. Termina sola cuando se acaba su tiempo, o elige **Finalizar carrera** para terminarla antes.',
						'Los móviles de los corredores hacen la cuenta atrás hasta la salida con el reloj del servidor y dicen en voz alta los últimos segundos, para que todos salgan a la vez.',
					],
				},
			],
		},
		{
			heading: 'El día de la carrera: cronometraje propio',
			blocks: [
				{
					type: 'list',
					items: [
						'No hay que pulsar nada. La ventana se abre y se cierra sola.',
						'Antes de que se abra puedes elegir **Retrasar salida** o **Cancelar**, como en una carrera programada.',
						'Mientras está abierta, introduce las horas y elige **Ampliar ventana** para mantenerla abierta más tiempo (hasta 7 días desde que se abrió), o elige **Cerrar la ventana ahora** para cerrarla antes.',
						'Cuando se cierra la ventana, un corredor que empezó un intento pero no envió resultado se marca como DNF, igual que cuando finalizas cualquier carrera.',
					],
				},
				{
					type: 'p',
					text: 'Cada recorrido necesita una línea de salida y una de meta, y se fijan para la carrera cuando se abre la ventana. Consulta [[guide:start-and-finish-lines|Líneas de salida y meta]].',
				},
			],
		},
		{
			heading: 'Aprobar resultados con cronometraje propio',
			blocks: [
				{
					type: 'p',
					text: 'En una carrera con cronometraje propio nadie está en la línea, así que por defecto sus resultados esperan tu aprobación: **Aprobar automáticamente los resultados enviados** empieza desmarcada. Cada resultado se muestra como **PENDIENTE** hasta que elijas **Aprobar**.',
				},
				{
					type: 'p',
					text: 'Algunos resultados se retienen para tu revisión aunque la aprobación automática esté activada: uno sin cruce de la línea de salida (de una versión antigua de la app o de un Apple Watch), uno que empieza fuera de la ventana y uno cuyos cruces no quedan respaldados por las propias posiciones en directo del corredor. Un corredor que cambia su propio tiempo también vuelve a pendiente.',
				},
				{
					type: 'p',
					text: 'Un corredor puede hacer varios intentos. Cuenta su mejor llegada cronometrada por las dos líneas, y un intento más lento no la sustituye.',
				},
			],
		},
		{
			heading: 'Avisos de salida inminente',
			blocks: [
				{
					type: 'p',
					text: 'Unos 10 minutos antes de un GO programado, todos los apuntados reciben una notificación push de que la carrera está a punto de empezar, salvo que les haya llegado un recordatorio del evento en la última hora. Cuando retrasas una salida, reciben otra que dice que ha cambiado. Estos avisos nunca se envían por correo electrónico.',
				},
				{
					type: 'p',
					text: 'Los corredores desactivan ambos con **Carrera a punto de empezar**: en la web, en [[route:/settings/notifications|Notificaciones]]; en la app del móvil, en **Notificaciones**, dentro de la pestaña **Tú**.',
				},
			],
		},
		{
			heading: 'Los corredores necesitan una app reciente',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Las carreras programadas y con cronometraje propio necesitan la última versión de la app en el móvil o el reloj Wear OS. Los resultados de versiones antiguas y del Apple Watch se guardan para tu revisión en lugar de rechazarse.',
				},
			],
		},
	],
	sources: {
		title: '8dd0bfbefd97b39d',
		summary: '5f79511dd816ce5e',
		's0.heading': '9b26470e1beae1e9',
		's0.b0.i0': '653b79ec7d550dc5',
		's0.b0.i1': '6824deac8c3239bb',
		's0.b0.i2': '86642ad5f00798d9',
		's0.b1': '8ec9d026a8e162d9',
		's1.heading': '8ec1ca546316bf44',
		's1.b0.i0': '7f4cdf51f946ad7a',
		's1.b0.i1': 'e945e787986a825b',
		's1.b1': 'dc8ad2296857c406',
		's1.b2': 'f73aee6a8e52f86d',
		's2.heading': '3b72a06be5feeca1',
		's2.b0': 'f8eb6df29239da40',
		's3.heading': '2e53337b73ea8f70',
		's3.b0.i0': '0cd2e7973bd13122',
		's3.b0.i1': 'bb292e4077fab06b',
		's3.b0.i2': '1001bcee9a695cbd',
		's3.b0.i3': 'ad3f370a0b11c0ea',
		's3.b0.i4': '8469b5a684fd410f',
		's4.heading': '5b67193948e22e2a',
		's4.b0.i0': '689b27335b1205f7',
		's4.b0.i1': '8835ede766aaa683',
		's4.b0.i2': '92ab0d9a0804d8f9',
		's4.b0.i3': 'fe1797aedc22317e',
		's4.b1': 'fe8c69f32f52d3b4',
		's5.heading': '32e61b0e9e8b093c',
		's5.b0': 'd72ed9b7c3434bf2',
		's5.b1': '8270611445444242',
		's5.b2': '80fde57d63447dcd',
		's6.heading': 'b0f6668439cdc509',
		's6.b0': '7f18ce5f91bea911',
		's6.b1': '75dcfe5f36ba4e0a',
		's7.heading': '81f746d1e62c98a8',
		's7.b0': '00727d27f2897451',
	},
};
