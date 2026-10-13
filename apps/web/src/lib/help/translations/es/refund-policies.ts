import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'refund-policies',
	source: 'be8b580dfc980abf',
	title: 'Políticas de reembolso y cancelación de tu inscripción',
	summary: 'Cómo funcionan las tres políticas de reembolso, cómo cancela un participante una inscripción de pago y qué ve al hacerlo.',
	sections: [
		{
			heading: 'Antes de empezar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'La inscripción de pago aún no está activa. Necesita que el organizador tenga conectada su cuenta de Stripe y que la plataforma active su sistema de pagos. Hasta entonces no se puede cobrar por ningún evento, así que no hay nada que reembolsar.',
				},
			],
		},
		{
			heading: 'Las tres políticas',
			blocks: [
				{
					type: 'p',
					text: 'El organizador elige una **Política de reembolso** al crear un evento de pago. Decide qué recupera alguien si cancela *por su cuenta*, y se muestra en la página del evento antes de que nadie pague.',
				},
				{
					type: 'list',
					items: [
						'**Reembolso completo hasta la hora de inicio**: los participantes la ven como **Cancelación gratuita hasta que empiece el evento**.',
						'**Reembolso completo hasta 24 h antes**: se muestra como **Cancelación gratuita hasta 24 horas antes del inicio**. Es la opción predeterminada.',
						'**Sin reembolsos**: se muestra como **Sin reembolso por cancelación**.',
					],
				},
				{
					type: 'p',
					text: 'Un reembolso es todo o nada: dentro del plazo recuperas el precio completo y fuera de él no recuperas nada. El plazo se mide respecto al inicio de la ocurrencia en la que te inscribiste.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'La política solo cubre la cancelación por parte de un participante. Si el organizador cancela una clase, a todas las personas que pagaron se les reembolsa el importe completo, diga lo que diga la política: consulta [[guide:cancel-a-class|Cancelar una clase]].',
				},
			],
		},
		{
			heading: 'Cancelar tu propia inscripción',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre el evento en la web. Donde dice **Estás inscrito**, pulsa **Cancelar inscripción**.',
						'Lee el cuadro de diálogo. Dentro del plazo de reembolso indica que se te reembolsará en tu método de pago original y que tu plaza queda libre para alguien de la lista de espera.',
						'Pulsa **Cancelar inscripción** para continuar, o **Conservar mi plaza** para echarte atrás.',
					],
				},
				{
					type: 'p',
					text: 'Cuando se completa, verás **Reembolso iniciado: puede tardar unos días en aparecer. Tu plaza ha quedado libre.** Hasta que tu banco lo confirme, la página muestra **Reembolso en curso**.',
				},
				{
					type: 'p',
					text: 'Si saliste del proceso de pago antes de pagar, el mismo botón cancela en su lugar la inscripción pendiente: tu plaza reservada se libera y no se cobra ningún pago.',
				},
			],
		},
		{
			heading: 'Fuera del plazo de reembolso',
			blocks: [
				{
					type: 'p',
					text: 'Pasado el plazo, o en un evento **Sin reembolsos**, la app no puede cancelar tu inscripción por ti. El cuadro de diálogo te avisa antes de intentarlo, conservas tu plaza y, si sigues adelante, verás **Esta inscripción está fuera del plazo de reembolso. Contacta con el organizador para cancelar.**',
				},
			],
		},
		{
			heading: 'Si un reembolso no llega',
			blocks: [
				{
					type: 'p',
					text: 'De vez en cuando, un banco devuelve un reembolso. La página del evento muestra entonces **Tu reembolso no te ha llegado** y una notificación dice **Un reembolso no se completó: nos pondremos en contacto**. No tienes que volver a pagar; usa **Contactar con facturación** y se te devolverá por otra vía.',
				},
			],
		},
	],
};
