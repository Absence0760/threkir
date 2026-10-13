import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'cancel-a-class',
	source: '8ee15ec25324129c',
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
};
