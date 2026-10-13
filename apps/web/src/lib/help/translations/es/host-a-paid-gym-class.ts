import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'host-a-paid-gym-class',
	source: '3b7a87855005ee69',
	title: 'Organizar una clase de pago de HIIT, fuerza o bootcamp',
	summary: 'Programa una clase de gimnasio recurrente con plazas limitadas y precio por sesión, comparte el entrenamiento como rutina del club y deja que cada asistente lo registre en su historial.',
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
					type: 'p',
					text: 'Tienes que ser administrador u organizador de eventos del club. El precio, el aforo y la programación de repetición se configuran en la web; la app móvil puede crear una clase, pero no tiene campos para ellos.',
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
						'En **Tipo de evento**, elige **Clase**. La ruta, la distancia, el ritmo y los resultados de carrera se ocultan en una clase.',
						'Rellena **Disciplina**, por ejemplo «HIIT» o «Bootcamp», y un **Título** que la gente reconozca en el calendario.',
						'Pon en **Duración predeterminada del entrenamiento** la duración de la clase en minutos. Esto es lo que permite a los asistentes registrar la clase con un toque después.',
						'Indica la **Fecha**, la **Hora de inicio**, la **Duración** y el **Punto de encuentro**.',
						'En **Repetición**, elige **Semanal**, **Cada 2 semanas** o **Mensual** y los días. Solo puedes elegirlo al crear el evento.',
						'Pon en **Aforo** el número de racks, bicis o plazas que tienes.',
						'Activa **Cobrar por este evento** y luego indica **Precio**, **Moneda**, **Cerrar ventas (minutos antes del inicio)** y una **Política de reembolso**. El precio y la moneda no se pueden cambiar después de crear el evento.',
						'Pulsa **Crear evento**.',
					],
				},
			],
		},
		{
			heading: 'Compartir el entrenamiento con tu clase',
			blocks: [
				{
					type: 'p',
					text: 'Una clase aún no puede llevar una rutina de gimnasio directamente. En su lugar, publica tu rutina en el club, donde los miembros pueden copiarla en sus propias rutinas y hacerla.',
				},
				{
					type: 'steps',
					items: [
						'Crea la rutina: consulta [[guide:build-a-gym-routine|Crear una rutina de gimnasio]].',
						'Abre la rutina y, en **Publicar en un club**, elige tu club en **Elige un club…** y pulsa **Publicar**.',
						'Aparece en la pestaña **Plantillas** del club, en **Plantillas de rutina de gimnasio**, marcada como **Plantilla del club**. Los miembros pulsan **Adoptar** para obtener su propia copia.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Los administradores del club también pueden ir directamente a la pestaña **Plantillas**, pulsar **Añadir plantilla** y elegir **Rutina de gimnasio**. Se guarda como plantilla del club en un solo paso.',
				},
			],
		},
		{
			heading: 'Los asistentes registran la clase en su propio historial',
			blocks: [
				{
					type: 'p',
					text: 'En la página de la clase, cualquier asistente con la sesión iniciada ve **Registrar como entrenamiento**. Abre un registro de gimnasio ya con el nombre de la clase, que puede ajustar con sus propias series y pesos antes de guardarlo. Después ve **Añadido a tu registro de gimnasio**, y la clase cuenta en su historial de entrenamiento como cualquier otro entrenamiento. Funciona en la web y en la app móvil.',
				},
				{
					type: 'p',
					text: 'Quien haya adoptado tu rutina puede, en cambio, abrirla y pulsar **Iniciar rutina** para que se le guíe serie a serie; esa sesión también se guarda en su registro de gimnasio.',
				},
			],
		},
		{
			heading: 'Inscripción, el día de la clase y cambios',
			blocks: [
				{
					type: 'list',
					items: [
						'Los asistentes se inscriben y pagan en la web, ven **Estás inscrito** y pueden cancelar según tu [[guide:refund-policies|política de reembolso]].',
						'Cuando se ocupan las plazas aparece **Agotado** y se ofrece **Unirme a la lista de espera**: consulta [[guide:waitlist-and-claim-window|Listas de espera y el plazo de 12 horas para reclamar la plaza]].',
						'Marca quién vino: [[guide:take-attendance|Pasar lista]].',
						'Cancelar una sesión reembolsa a todas las personas que pagaron: [[guide:cancel-a-class|Cancelar una clase]].',
					],
				},
			],
		},
	],
};
