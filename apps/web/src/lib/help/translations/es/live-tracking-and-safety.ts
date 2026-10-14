import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'live-tracking-and-safety',
	title: 'Seguimiento en directo y contactos de seguridad',
	summary: 'Deja que alguien siga tu carrera en directo y haz que tus contactos de confianza reciban un correo cuando termines, dejes de dar señales o no hayas vuelto a tiempo.',
	sections: [
		{
			heading: 'Compartir un enlace en directo',
			blocks: [
				{
					type: 'steps',
					items: [
						'Inicia sesión en la app del móvil. Un enlace en directo solo funciona si has iniciado sesión.',
						'En la pantalla de carrera, antes de empezar, toca **Compartir enlace en vivo** y envíalo con cualquier app de tu móvil.',
						'Toca **INICIAR**. El enlace se activa cuando empieza la carrera.',
					],
				},
				{
					type: 'p',
					text: 'Quien tenga el enlace puede abrirlo en un navegador y ver tu posición y tus datos, sin necesidad de cuenta. Las zonas de privacidad también se aplican al mapa en directo.',
				},
				{
					type: 'p',
					text: 'Mientras compartes, aparece la insignia **En vivo** en la pantalla de grabación. Tócala para **Compartir enlace de nuevo**, **Dejar de compartir** o fijar una hora en **Sin volver a las…**.',
				},
				{
					type: 'p',
					text: 'Cuando termina la carrera, el enlace deja de actualizarse. Si tus carreras normalmente no son públicas, se te pregunta si quieres **Mantener pública** la carrera guardada para quienes tengan el enlace; si no, vuelve a tu privacidad habitual de las carreras.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Para compartir todas tus carreras sin tener que acordarte, activa **Directo automático** en **Contactos de seguridad**, dentro de la pestaña **Tú**. Solo se aplica a ese móvil, y cualquiera con el enlace puede ver la carrera en curso.',
				},
				{
					type: 'illustration',
					id: 'live-tracking-and-safety',
					alt: 'El móvil de un corredor envía su posición en directo a dos personas, que la siguen cada una en su propia pantalla.',
				},
			],
		},
		{
			heading: 'Añadir contactos de seguridad',
			blocks: [
				{
					type: 'p',
					text: 'Un contacto de seguridad es alguien de confianza, como tu pareja, un amigo o un familiar. Recibe un correo cuando terminas una carrera, incluso una privada, para que sepa que has vuelto.',
				},
				{
					type: 'steps',
					items: [
						'En la web, abre [[route:/settings/safety|Seguridad]] en Configuración; en la app del móvil, abre **Contactos de seguridad** en la pestaña **Tú**.',
						'Introduce su **Correo del contacto**. También puedes añadir un **Teléfono para SMS (opcional)** en formato internacional, como +447700900123.',
						'Selecciona **Añadir contacto**. Recibirá un correo en el que se le pide que confirme.',
						'Su estado muestra **Pendiente: esperando su confirmación** hasta que acepte, y después **Confirmado**. Solo se avisa a los contactos confirmados.',
					],
				},
				{
					type: 'p',
					text: 'Si alguien te añade como contacto, la solicitud aparece en **Solicitudes para ti**, donde puedes **Confirmar** o **Rechazar**. Más adelante, en **Eres contacto de seguridad**, puedes cambiar cómo se te avisa o **Retirarme**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Los avisos por correo se envían siempre. Los mensajes de texto requieren además que el contacto lo acepte al confirmar, y el envío de SMS todavía no está activado en todas partes, así que no confíes solo en los SMS.',
				},
			],
		},
		{
			heading: 'Avisos cuando algo parece ir mal',
			blocks: [
				{
					type: 'p',
					text: 'Estos avisos solo cubren carreras con el directo activado, porque el enlace en directo es lo que nos dice dónde estás. Cada contacto recibe como máximo un aviso por carrera.',
				},
				{
					type: 'list',
					items: [
						'**Alerta de retraso**: elige un tiempo en **Avisar a los contactos tras un silencio de** en la web, o en **Avisar tras un silencio de** en la app. Si tu carrera en directo no envía nada durante ese tiempo, tus contactos confirmados reciben por correo tu enlace en directo. Está **Desactivado** hasta que elijas un tiempo.',
						'**Sin volver a las…**: durante una carrera compartida en directo, toca la insignia **En vivo** y elige cuándo esperas terminar. Si la carrera sigue en marcha a esa hora, se avisa a tus contactos. La hora se guarda en nuestro servidor, así que cuenta aunque tu móvil se quede sin batería. También puedes fijarla desde tu propia página en directo en la web.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Perder la cobertura del móvil parece lo mismo que dejar de dar señales, y una carrera que termina sin cobertura aún puede disparar un aviso hasta que se suba. El correo indica a tus contactos que la pérdida de señal es una posible causa.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ya existe un aviso automático a tus contactos cuando te sales de la ruta prevista, pero todavía no está activado. Hasta que lo esté, el ajuste **Aviso de salida de ruta** permanece oculto.',
				},
			],
		},
		{
			heading: 'Avisos de salida de ruta mientras corres',
			blocks: [
				{
					type: 'p',
					text: 'Si sigues una ruta guardada, la pantalla de carrera te avisa cuando te desvías de ella, mostrando a qué distancia estás, y puede decirlo en voz alta si tienes activados los avisos de audio. Este aviso es para ti; no contacta con nadie.',
				},
			],
		},
	],
	sources: {
		title: 'cee4d0a20867ed19',
		summary: '45984309810e4f6b',
		's0.heading': 'dc5c5a630221dbbc',
		's0.b0.i0': 'f62182995094fa0a',
		's0.b0.i1': '5df8617dc302468a',
		's0.b0.i2': 'fd23a78c3f8edbbd',
		's0.b1': 'f45b4fcfccc4fb7e',
		's0.b2': '7845c9dd61f6fcbd',
		's0.b3': '21b6940abd1d8d09',
		's0.b4': '822ce03c51253ce8',
		's1.heading': '7fe0f3d3bca83ca6',
		's1.b0': '8983069471135762',
		's1.b1.i0': '6675420e0916edbb',
		's1.b1.i1': '8ad53d18b45a91df',
		's1.b1.i2': '921f48df34ed7a60',
		's1.b1.i3': 'fb0e10c56d0013a1',
		's1.b2': 'd5654527a9969a6c',
		's1.b3': '38a6734637422840',
		's2.heading': '6494ef66d8a744ee',
		's2.b0': '3076b2df5cf96aca',
		's2.b1.i0': 'd1a279384aa709ce',
		's2.b1.i1': '43b13b285ccc1278',
		's2.b2': '968742a451f6aa8a',
		's2.b3': '0694224872716044',
		's3.heading': '4799e1fbd28720f2',
		's3.b0': '2557edbaef77cc2c',
		's0.b5': 'eb575f135ac66d66',
	},
};
