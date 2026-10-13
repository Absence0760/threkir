import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'recurring-events',
	source: 'd308eeb2564d2425',
	title: 'Configurar un evento recurrente del club',
	summary: 'Convierte un evento del club en una serie semanal, quincenal o mensual, confirma tu asistencia a una sola fecha y cancela una ocurrencia sin tocar el resto.',
	sections: [
		{
			heading: 'Crear la serie',
			blocks: [
				{
					type: 'p',
					text: 'Los propietarios, administradores y organizadores de eventos del club pueden crear eventos. Un evento recurrente es un único evento que se repite, así que todo lo que rellenes se aplica a todas las fechas.',
				},
				{
					type: 'steps',
					items: [
						'Abre tu club en la web y selecciona **Nuevo evento**.',
						'Rellena el **Título**, la **Hora de inicio** y los demás datos como en un evento único. La hora de inicio que elijas es la primera fecha de la serie.',
						'En **Repetición**, elige **Semanal**, **Cada 2 semanas** o **Mensual** en lugar de **Una vez**.',
						'En una serie semanal o quincenal, elige los días de la semana en **En estos días:**. Una serie mensual se repite el mismo día del mes que la fecha de inicio.',
						'Decide cuándo termina la serie: pon una fecha en **Termina el**, un número de ocurrencias en **Termina tras**, o ambas cosas, y manda lo que llegue antes. Si dejas los dos vacíos, se sigue repitiendo.',
						'Selecciona **Crear evento**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'El patrón de repetición solo se puede elegir al crear el evento. **Editar evento** cambia el título, la hora, el punto de encuentro y los demás datos de toda la serie, pero no la frecuencia con la que se repite.',
				},
				{
					type: 'p',
					text: 'En la app móvil, toca **Crear evento** en la pestaña **Eventos** del club y elige **Semanal**, **Quincenal** o **Mensual** en **Repetición**. El móvil repite el evento el mismo día de la semana que su fecha de inicio y no tiene fecha de fin ni número de ocurrencias, así que usa la web si la serie tiene que terminar.',
				},
			],
		},
		{
			heading: 'Confirmar asistencia a una fecha',
			blocks: [
				{
					type: 'p',
					text: 'Cada fecha de una serie tiene sus propias confirmaciones de asistencia, lista de asistentes, aforo y resultados.',
				},
				{
					type: 'steps',
					items: [
						'Abre el evento y usa **Elige una ocurrencia** para escoger la fecha. Se muestran las próximas fechas, y **Mostrar las próximas** despliega todas las fechas del próximo año.',
						'Elige **Me apunto**, **Quizás** o **No puedo** para esa fecha.',
					],
				},
				{
					type: 'p',
					text: 'Para añadir las fechas a tu propio calendario, selecciona **Añadir al calendario**. En una serie puedes elegir **Añadir esta fecha** para una sola fecha o **Añadir toda la serie** para todas.',
				},
			],
		},
		{
			heading: 'Cancelar una ocurrencia',
			blocks: [
				{
					type: 'p',
					text: 'Si una fecha no puede celebrarse, cancela solo esa fecha y deja el resto de la serie como está.',
				},
				{
					type: 'steps',
					items: [
						'Abre el evento en la web y elige la fecha que tienes que cancelar.',
						'Selecciona **Cancelar esta ocurrencia**.',
						'Añade un **Motivo (opcional)**, como un recorrido inundado o un día festivo, y confirma. Selecciona **Mantener** si cambias de opinión.',
					],
				},
				{
					type: 'p',
					text: 'Todas las personas que confirmaron su asistencia a esa fecha, tanto si iban, como si respondieron quizás o estaban en lista de espera, reciben una notificación. La fecha muestra **Esta ocurrencia se canceló.** y nadie puede confirmar asistencia a ella. Para recuperarla, abre la fecha y selecciona **Restablecer esta ocurrencia**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Cancelar y restablecer una fecha solo se puede hacer en la web. **Eliminar evento** elimina todas las ocurrencias de la serie, no solo una.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si el evento es una clase de pago, cancelar una ocurrencia reembolsa el importe completo a todas las personas inscritas en ella. Consulta [[guide:host-a-paid-yoga-class|Organizar una clase de pago de yoga]].',
				},
			],
		},
	],
};
