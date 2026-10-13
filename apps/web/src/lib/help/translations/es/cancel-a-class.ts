import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'cancel-a-class',
	title: 'Cancelar una clase y reembolsar a quienes pagaron',
	summary: 'Cancela una ocurrencia de una clase que se repite; a quienes pagaron se les reembolsa todo automáticamente, con un reintento cada hora y la opción Reembolsar ahora.',
	sections: [
		{
			heading: 'Antes de empezar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Las clases de pago aún no están activas: necesitan que el organizador tenga conectada su cuenta de Stripe y que la plataforma active su sistema de pagos. Si los pagos no están disponibles cuando intentas cancelar una ocurrencia que tiene inscripciones pagadas, verás **Esta ocurrencia tiene inscripciones pagadas y los pagos no están disponibles ahora mismo, así que todavía no se puede cancelar. No se ha cambiado nada.** La clase sigue en pie, para que nadie se quede con un pago hecho por una clase que no se va a celebrar.',
				},
				{
					type: 'p',
					text: 'Cancelar es cosa de los administradores y organizadores de eventos del club, y se hace en la web. Las clases gratuitas se cancelan igual, solo que sin reembolsos.',
				},
			],
		},
		{
			heading: 'Cancelar una ocurrencia',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre la clase en la web. Si se repite, usa **Elige una ocurrencia** para escoger la fecha que vas a cancelar.',
						'Pulsa **Cancelar esta ocurrencia**.',
						'El cuadro de diálogo explica que solo se cancela esta ocurrencia y que el resto de la serie no se ve afectado. En una clase de pago añade: **Todas las personas inscritas en esta ocurrencia reciben el reembolso completo, sea cual sea la política de reembolso.**',
						'Si quieres, añade un **Motivo (opcional)** y vuelve a pulsar **Cancelar esta ocurrencia** para confirmar, o **Mantener** para echarte atrás.',
					],
				},
				{
					type: 'p',
					text: 'Al terminar verás a cuántas personas se está reembolsando, por ejemplo *Ocurrencia cancelada. 8 personas inscritas reciben el reembolso completo.* A quien estaba a mitad del pago se le libera la plaza reservada y no se le cobra. Nadie de la lista de espera pasa a una clase cancelada.',
				},
			],
		},
		{
			heading: 'Qué se les dice a tus asistentes',
			blocks: [
				{
					type: 'p',
					text: 'Todas las personas que confirmaron su asistencia a esa ocurrencia (asisten, quizás o en lista de espera) reciben un aviso. Quienes pagaron reciben una notificación como *Se canceló una ocurrencia de «Reformer del martes»: te estamos reembolsando el pago*, y el mismo texto se envía por correo o por notificación push a quien los recibe. Dice *estamos reembolsando* porque el reembolso se inicia en ese momento y puede tardar unos días en llegar a su banco.',
				},
			],
		},
		{
			heading: 'Si falla un reembolso',
			blocks: [
				{
					type: 'p',
					text: 'La ocurrencia queda cancelada aunque Stripe rechace un reembolso. Verás un mensaje que indica cuántos reembolsos no se pudieron iniciar, y la página de la clase muestra una tarjeta **Reembolsos de ocurrencias canceladas** que indica, por cada fecha cancelada, a quién no se ha reembolsado todavía, qué reembolsos están en curso y cuáles ha devuelto el banco.',
				},
				{
					type: 'list',
					items: [
						'La app reintenta automáticamente, una vez por hora, todos los reembolsos pendientes de una clase cancelada.',
						'No hace falta esperar: pulsa **Reembolsar ahora** junto a la ocurrencia para volver a intentarlo al momento. Nunca reembolsa dos veces a nadie.',
						'Un reembolso que devuelve el banco no se puede reintentar así; se le devuelve a la persona por otra vía.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'No reembolses a mano desde un panel de Stripe. Un reembolso hecho ahí puede no revertir tu pago ni la comisión de la plataforma, y la app podría luego reembolsar el resto además. Usa **Reembolsar ahora** en su lugar.',
				},
			],
		},
		{
			heading: 'Clases únicas y series completas',
			blocks: [
				{
					type: 'p',
					text: '**Cancelar esta ocurrencia** solo se ofrece en una clase que se repite. No hay un único botón para cancelar una serie completa: cancela cada próxima ocurrencia que tenga inscripciones.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: '**Eliminar evento** no es una cancelación. Elimina el evento y todas sus ocurrencias y no reembolsa a nadie que haya pagado. No elimines una clase de pago que aún tenga inscripciones.',
				},
				{
					type: 'p',
					text: '¿Has cambiado de opinión? **Restablecer esta ocurrencia** vuelve a poner una fecha cancelada en el calendario, pero los reembolsos ya hechos no se deshacen, así que las personas tendrán que volver a inscribirse.',
				},
			],
		},
	],
	sources: {
		title: '539c07215344e21b',
		summary: '3cde6837a6c4e13c',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': 'ae0f2cd6ce9f9514',
		's0.b1': '62f19ee1e9fb34c3',
		's1.heading': 'f95356ca142cc32c',
		's1.b0.i0': '98e1807ee36d2ae0',
		's1.b0.i1': '63ef622195f62b11',
		's1.b0.i2': '876f86b1b4e1070e',
		's1.b0.i3': '4aa8c04940065d46',
		's1.b1': '0d59321bed0664c0',
		's2.heading': '3fb0e8cd8d1ab1a9',
		's2.b0': '7fa0c327762bc337',
		's3.heading': '9ea612affe97dc23',
		's3.b0': '734dd195583da93f',
		's3.b1.i0': 'a63f61852a0c3de7',
		's3.b1.i1': '7f81dbe53b5fa733',
		's3.b1.i2': '17e04336cbe74225',
		's3.b2': '28dcde6e29894cdf',
		's4.heading': '335c84d82f12cfd6',
		's4.b0': 'bf92582fcb35608a',
		's4.b1': 'ccac613bf1514e51',
		's4.b2': '79b6ac5d2f43064a',
	},
};
