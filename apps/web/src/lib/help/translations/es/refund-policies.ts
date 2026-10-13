import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'refund-policies',
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
	sources: {
		title: 'c4fa256f459076d1',
		summary: '9baf65491beccb1b',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '30a11867ccf5b3d2',
		's1.heading': '9b547a04e62b40db',
		's1.b0': 'ac02c018440619c7',
		's1.b1.i0': '78212cc5dd0fc966',
		's1.b1.i1': '109e0ad8958dff1d',
		's1.b1.i2': 'c0df4938a31c7529',
		's1.b2': 'f6431402b8fb3d47',
		's1.b3': '2ba18e4b6ad11943',
		's2.heading': '75a59fd46f7b58e9',
		's2.b0.i0': '6acdfa50019e0f37',
		's2.b0.i1': '46cf562b1c2b6db6',
		's2.b0.i2': '769ffd95161fd1d5',
		's2.b1': '36a76c72aba97bcd',
		's2.b2': '3cd5377cc8a2bfcf',
		's3.heading': '41bf02bef2f3e906',
		's3.b0': '79864fedf6e2a3a4',
		's4.heading': '9bc91646456ca461',
		's4.b0': '99e677611ddc18a9',
	},
};
