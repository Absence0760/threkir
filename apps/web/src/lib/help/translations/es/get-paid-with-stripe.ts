import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'get-paid-with-stripe',
	source: 'd4950e6117ea250a',
	title: 'Cobrar por los eventos que organizas',
	summary: 'Conecta una vez una cuenta de pagos de Stripe para que las clases y eventos que organizas puedan cobrar, y el dinero vaya a ti y no al club.',
	sections: [
		{
			heading: 'Antes de empezar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'La inscripción de pago aún no está activa. Cobrar por un evento requiere dos cosas: tu propia cuenta de Stripe conectada aquí y que la plataforma active su sistema de pagos. Hasta que se cumplan ambas, no se puede cobrar a nadie. Si al pulsar **Configurar pagos** aparece **Los pagos aún no están configurados en esta versión.**, falta la segunda y por ahora no tienes nada que hacer.',
				},
				{
					type: 'p',
					text: 'Los pagos te corresponden *a ti*, no a un club. El dinero de un evento va a la persona que lo organiza, así que un coorganizador que nunca organiza una clase nunca ve dinero que no es suyo, y conservas tus ingresos si dejas de organizar para un club. Una sola cuenta de pagos cubre todos los clubes para los que organizas y todo tipo de eventos, incluida una [[guide:set-up-a-race|carrera]].',
				},
			],
		},
		{
			heading: 'Conectar tu cuenta de pagos',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre [[route:/settings/payouts|Configuración, Pagos]] en la web.',
						'Pulsa **Configurar pagos**. Irás a Stripe para introducir tus datos y la cuenta bancaria en la que quieres cobrar.',
						'Completa los pasos de Stripe. Cuando vuelvas, la página mostrará tu estado.',
						'Si dice **Configuración incompleta: termínala para empezar a cobrar** o **Tu cuenta de pagos requiere atención antes de poder cobrar**, pulsa **Terminar de configurar los pagos** para volver a Stripe y seguir donde lo dejaste.',
					],
				},
			],
		},
		{
			heading: 'Qué significa el estado',
			blocks: [
				{
					type: 'list',
					items: [
						'**Listo para cobrar**: Stripe ha habilitado los cargos en tu cuenta, y **Abrir el panel de Stripe** te lleva a tu cuenta de Stripe. Esto es lo que significa «cargos habilitados», y es el único estado en el que se puede activar el interruptor **Cobrar por este evento** de un evento nuevo.',
						'**Configuración incompleta: termínala para empezar a cobrar**: Stripe aún necesita algo de ti antes de aceptar un cargo.',
						'**Tu cuenta de pagos requiere atención antes de poder cobrar**: Stripe ha restringido la cuenta, normalmente porque quiere más información. **Terminar de configurar los pagos** te lleva a lo que está pidiendo.',
					],
				},
				{
					type: 'p',
					text: 'Hasta que estés listo para cobrar, el formulario del evento muestra **Configura los pagos para cobrar por eventos.** con un enlace **Configurar pagos** que vuelve a esta página.',
				},
			],
		},
		{
			heading: 'Comisiones y quién se ocupa de qué',
			blocks: [
				{
					type: 'p',
					text: 'La plataforma se queda una pequeña comisión de cada inscripción, que aparece como **Comisión de la plataforma** en tus ingresos. La plataforma es el comerciante registrado: el cargo aparece a su nombre en el extracto de quien compra, los reembolsos los emite la plataforma según la política de reembolso que fijes en cada evento, y un cargo disputado se debita de la cuenta de Stripe de la plataforma, no de la tuya. Cuando un pedido se reembolsa por completo, también se devuelve la comisión de la plataforma de ese pedido.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'No reembolses a un comprador a mano en Stripe. Usa las vías de la propia app ([[guide:refund-policies|la cancelación de un comprador]] o [[guide:cancel-a-class|cancelar una ocurrencia]]), que revierten a la vez tu pago y la comisión de la plataforma y mantienen correctas tus cifras de ingresos.',
				},
			],
		},
		{
			heading: 'Consultar lo que has ganado',
			blocks: [
				{
					type: 'p',
					text: 'La sección **Ingresos** de la misma página muestra lo que te pagaron por tus clases, con un bloque por mes y moneda. Cada clase se asigna al mes en que se impartió en su propia zona horaria, no al mes en que alguien pagó, así que «mis clases de octubre» son las clases que se celebraron en octubre.',
				},
				{
					type: 'list',
					items: [
						'**Inscripciones**, **Bruto**, **Reembolsado** y **Comisión de la plataforma** del mes y, al final, **Neto para ti**.',
						'Un desglose por clase con las columnas **Clase** y **Cuándo**.',
						'Un reembolso que el banco devolvió queda fuera de los totales hasta que se resuelve, y la sección indica cuántos hay.',
					],
				},
				{
					type: 'p',
					text: 'Antes de que nadie haya pagado, dice **Aún no hay inscripciones pagadas. Cuando alguien pague una de tus clases, aparecerá aquí.** Por ahora, los ingresos solo se pueden ver en la web.',
				},
			],
		},
	],
};
