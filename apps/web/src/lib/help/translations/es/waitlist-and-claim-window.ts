import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'waitlist-and-claim-window',
	title: 'Listas de espera y el plazo de 12 horas para reclamar la plaza',
	summary: 'Cómo funciona apuntarse a una clase llena, cómo se te guarda 12 horas una plaza liberada en una clase de pago y qué pasa si no la reclamas.',
	sections: [
		{
			heading: 'Clases gratuitas: entras automáticamente',
			blocks: [
				{
					type: 'p',
					text: 'Cuando una clase gratuita con **Aforo** está llena, al pulsar **Me apunto** pasas a la lista de espera y tu respuesta muestra **En lista de espera**. Cuando alguien se da de baja, la primera persona de la lista de espera pasa automáticamente a **Asiste**; no hay nada que reclamar. Funciona en la web y en la app móvil.',
				},
			],
		},
		{
			heading: 'Clases de pago: se guarda una plaza y luego pagas',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Las clases de pago aún no están activas: necesitan que el organizador tenga conectada su cuenta de Stripe y que la plataforma active su sistema de pagos. Todo lo de esta sección se aplica una vez que lo estén.',
				},
				{
					type: 'p',
					text: 'A nadie se le cobra solo por estar en una lista de espera. En su lugar, cuando se libera una plaza se te ofrece y pagas para quedártela.',
				},
				{
					type: 'steps',
					items: [
						'En una clase de pago llena, la página muestra **Agotado**. Mientras la venta siga abierta, pulsa **Unirme a la lista de espera**. Verás **Estás en la lista de espera. Si se libera una plaza, te la guardaremos y te avisaremos.**',
						'Cuando se libera una plaza y eres la primera persona de la lista, recibes una notificación: *Se ha liberado una plaza en «Reformer del martes» y te la guardamos: paga para conseguirla*.',
						'Abre la clase en la web. Indica cuándo termina tu reserva, por ejemplo *Te guardamos una plaza hasta martes, 6 de mayo, 18:00. Paga para conseguirla o pasará a la siguiente persona de la lista de espera.*',
						'Pulsa el botón para reclamarla (dice *Conseguir mi plaza* junto con el precio) y paga en el proceso de pago. Una vez pagado, quedas inscrito como todos los demás.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'La plaza se reclama en la web. La app móvil muestra la notificación y abre la clase, pero aún no tiene proceso de pago, así que abre la clase en un navegador para pagar.',
				},
				{
					type: 'illustration',
					id: 'waitlist-and-claim-window',
					alt: 'Tres personas esperan en la cola. A la primera se le ofrece la plaza libre, que se le reserva durante un tiempo limitado.',
				},
			],
		},
		{
			heading: 'Cuánto dura la reserva',
			blocks: [
				{
					type: 'list',
					items: [
						'Tienes 12 horas para reclamarla, tiempo suficiente para que nadie pierda una plaza por estar durmiendo.',
						'La reserva se acorta cuando se cierran las ventas de esa clase (la hora de cierre de ventas que fija el organizador antes del inicio). No se ofrece ninguna plaza después del cierre de ventas, porque nadie podría pagarla.',
						'Mientras tu plaza esté reservada, nadie más puede comprarla, aunque para ellos la clase parezca llena.',
						'Si estás a mitad del proceso de pago cuando se acaba el tiempo, la reserva se mantiene mientras ese proceso de pago siga abierto.',
					],
				},
			],
		},
		{
			heading: 'Si no la reclamas',
			blocks: [
				{
					type: 'p',
					text: 'Cuando se acaba la reserva, la plaza se ofrece a la siguiente persona de la lista de espera y tú sales de la lista. Si aún quieres entrar, vuelve a pulsar **Unirme a la lista de espera**; pasas al final de la cola.',
				},
				{
					type: 'p',
					text: '¿Has cambiado de opinión mientras esperas? Pulsa **Salir de la lista de espera**. Te avisa de que perderás tu puesto en la cola; si vuelves a apuntarte más tarde, pasas al final. Si ya se te está guardando una plaza y no la quieres, deja que la reserva caduque.',
				},
			],
		},
		{
			heading: 'Para organizadores',
			blocks: [
				{
					type: 'list',
					items: [
						'La lista de espera funciona sola. Indica un **Aforo** en la clase y el resto ocurre automáticamente; el plazo de 12 horas no se puede cambiar por clase.',
						'Una plaza reservada cuenta para tu aforo, así que nunca acabas con más personas que esterillas.',
						'Si alguien cancela con reembolso, su plaza pasa a la lista de espera. Si cancelas una ocurrencia, nadie de la lista de espera pasa a ella: consulta [[guide:cancel-a-class|Cancelar una clase]].',
					],
				},
			],
		},
	],
	sources: {
		title: 'ff29dd616c432abb',
		summary: 'afd5b04d5200ae72',
		's0.heading': '1a4ad94ad3a45f95',
		's0.b0': 'cc59a78b4fa99e3d',
		's1.heading': '45a160f0c13ecbad',
		's1.b0': '360073628758585f',
		's1.b1': '572cda34a27eb2a9',
		's1.b2.i0': '5ee5608e87186c87',
		's1.b2.i1': '8e62e44aa4cb3c4c',
		's1.b2.i2': '2411acbf338bf29b',
		's1.b2.i3': '3fc20f1431c75da8',
		's1.b3': 'ac88ce64fbfe661e',
		's2.heading': '3120ebc77dff029c',
		's2.b0.i0': 'ac867875f2d6559e',
		's2.b0.i1': '10c7227bdd74a7f7',
		's2.b0.i2': 'ec3aaee401a8d661',
		's2.b0.i3': '115c393a06a875a2',
		's3.heading': '1c4542c4b4456638',
		's3.b0': '5f2b4c5d07b65be4',
		's3.b1': '080220c843290021',
		's4.heading': '3475448cc5eb2d77',
		's4.b0.i0': '9fc9b8683d8e30fd',
		's4.b0.i1': 'f602296c6993b85f',
		's4.b0.i2': '4d6cf70ea800fae3',
		's1.b4': 'f0e75c06bd5e6193',
	},
};
