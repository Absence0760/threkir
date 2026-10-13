import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'host-a-paid-yoga-class',
	source: '0781bf399db08c5b',
	title: 'Organizar una clase de pago de yoga o pilates',
	summary: 'Programa una clase recurrente para tu club, limita las esterillas, fija un precio por sesión y una política de reembolso, y añade una secuencia cronometrada para seguirla.',
	sections: [
		{
			heading: 'Antes de empezar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Las clases de pago aún no están activas. Para cobrar necesitas tener conectada tu propia cuenta de Stripe ([[guide:get-paid-with-stripe|Cobrar por los eventos que organizas]]) y que la plataforma active su sistema de pagos. Hasta entonces, el interruptor **Cobrar por este evento** sigue desactivado y puedes impartir la clase gratis.',
				},
				{
					type: 'list',
					items: [
						'Tienes que ser administrador u organizador de eventos del club. La página del club te indica cuál eres con **Eres administrador** o **Eres organizador de eventos**.',
						'El precio, el aforo, la programación de repetición y el plan de sesión se configuran en la web. La app móvil puede crear una clase y mostrarla a los miembros, pero no tiene campos de precio, aforo ni plan de sesión.',
						'Si quieres asociar una secuencia, créala primero: consulta [[guide:build-a-session-plan|Crear un plan de sesión]].',
					],
				},
			],
		},
		{
			heading: 'Crear la clase',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre tu club, ve a la pestaña **Eventos** y pulsa **Nuevo evento**.',
						'En **Tipo de evento**, elige **Clase**. La ruta, la distancia, el ritmo y los resultados de carrera desaparecen, porque una clase no los necesita.',
						'Rellena **Disciplina**, por ejemplo «Pilates reformer». Indica el estilo en el anuncio.',
						'Si quieres, indica la **Duración predeterminada del entrenamiento** en minutos. Con una disciplina o una duración indicada, los asistentes tienen un botón **Registrar como entrenamiento** en la página de la clase.',
						'Si quieres, elige un **Plan de sesión** para asociar tu secuencia cronometrada. Si lo dejas en **Ninguno**, la clase se imparte sin secuencia.',
						'Ponle un **Título** y luego la **Fecha**, la **Hora de inicio**, la **Duración** y un **Punto de encuentro** que alguien de fuera pueda encontrar, como la dirección del estudio.',
					],
				},
			],
		},
		{
			heading: 'Programación, aforo y precio',
			blocks: [
				{
					type: 'steps',
					items: [
						'En **Repetición**, elige **Semanal**, **Cada 2 semanas** o **Mensual**, luego los días y cuándo termina la serie con **Termina el** o **Termina tras**. La programación solo se puede elegir mientras creas el evento.',
						'Pon en **Aforo** el número de esterillas. Cuando haya ese número de personas inscritas, la siguiente pasa a una lista de espera.',
						'Activa **Cobrar por este evento** e introduce el **Precio** y la **Moneda**. Ninguno de los dos se puede cambiar una vez creado el evento, así que revísalos ahora.',
						'Indica **Cerrar ventas (minutos antes del inicio)**. Con cero, la inscripción sigue abierta hasta el mismo inicio.',
						'Elige una **Política de reembolso**: **Reembolso completo hasta la hora de inicio**, **Reembolso completo hasta 24 h antes** o **Sin reembolsos**. Consulta [[guide:refund-policies|Políticas de reembolso]].',
						'Pulsa **Crear evento**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'La inscripción de pago es solo para clases presenciales. Cada ocurrencia de una clase que se repite se paga por separado, como una sesión suelta.',
				},
			],
		},
		{
			heading: 'Qué ven tus asistentes',
			blocks: [
				{
					type: 'list',
					items: [
						'La disciplina, la hora, el lugar, el **Precio** y una línea sobre la cancelación, como **Cancelación gratuita hasta 24 horas antes del inicio**.',
						'Un botón que dice *Inscribirse · 22,00 US$* (con tu precio) y que lleva al pago. Cuando vuelven, dice **Pago confirmado: estás inscrito.**',
						'**Agotado** cuando se ocupan las esterillas, con **Unirme a la lista de espera** mientras la venta está abierta ([[guide:waitlist-and-claim-window|cómo funciona la lista de espera]]), e **Inscripción cerrada** cuando se cierran las ventas.',
						'Tu secuencia en **Secuencia de la sesión**. Pueden abrirla y pulsar **Iniciar sesión** para seguirla en casa.',
					],
				},
				{
					type: 'p',
					text: 'La inscripción y el pago se hacen en la web. La app móvil muestra la clase, pero aún no tiene botón de inscripción.',
				},
			],
		},
		{
			heading: 'El día de la clase y después',
			blocks: [
				{
					type: 'list',
					items: [
						'Marca quién vino: [[guide:take-attendance|Pasar lista]].',
						'¿Tienes que cancelar una? [[guide:cancel-a-class|Cancelar una clase]] reembolsa a todas las personas que pagaron.',
						'El dinero va a tu propia cuenta de pagos, menos la comisión de la plataforma, y aparece en **Ingresos**, en [[route:/settings/payouts|Pagos]].',
					],
				},
				{
					type: 'p',
					text: '¿Olvidaste el plan al crearla? En la página de la clase, los organizadores pueden usar **Asociar a un evento de clase** en la tarjeta **Secuencia de la sesión** para elegir uno más tarde.',
				},
			],
		},
	],
};
