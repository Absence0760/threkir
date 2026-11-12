import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'take-attendance',
	title: 'Pasar lista en una clase',
	summary: 'Marca quién vino de verdad a cada ocurrencia de una clase, aparte de quién dijo que vendría, en la web o en la app móvil.',
	sections: [
		{
			heading: 'Quién puede pasar lista y dónde',
			blocks: [
				{
					type: 'p',
					text: 'La asistencia es para eventos de tipo **Clase**, y solo los administradores y organizadores de eventos del club pueden marcarla. Funciona igual en la web y en la app móvil, así que puedes hacerlo desde el móvil al frente de la sala.',
				},
				{
					type: 'p',
					text: 'Es independiente de la confirmación de asistencia. Alguien puede figurar como **Asiste**, o estar inscrito y haber pagado, y aun así marcarse como ausente; marcar la asistencia nunca cambia su inscripción ni reembolsa a nadie.',
				},
			],
		},
		{
			heading: 'Marcar quién vino',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre la clase. Si se repite, usa **Elige una ocurrencia** para escoger la fecha de hoy, porque la asistencia se registra por ocurrencia.',
						'Desplázate hasta la lista de asistentes.',
						'Junto a cada persona, pulsa **Marcar como asistió** o **Marcar como ausente**.',
						'¿Has pulsado el que no era? Vuelve a pulsar el mismo botón para quitarlo.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'No tienes que marcar a todo el mundo. Quien quede sin marcar simplemente no tiene asistencia registrada.',
				},
			],
		},
		{
			heading: 'Qué ven los demás',
			blocks: [
				{
					type: 'p',
					text: 'Las demás personas que miran la clase ven una etiqueta **Asistió** o **Ausente** junto a cada nombre que marcaste, pero no pueden cambiarla.',
				},
				{
					type: 'p',
					text: 'La asistencia no añade la clase al historial de entrenamiento de nadie. Eso lo hacen los propios asistentes con **Registrar como entrenamiento** en la página de la clase, o siguiendo el plan de sesión de la clase: consulta [[guide:build-a-session-plan|Crear un plan de sesión]].',
				},
			],
		},
	],
	sources: {
		title: '8e94f2c520c4725e',
		summary: '19234d07e67c5a4f',
		's0.heading': 'faee9310c256dbe3',
		's0.b0': 'f196a1f6af265a97',
		's0.b1': '4e5ee5d97f6345cd',
		's1.heading': '606dabb8e1030b7c',
		's1.b0.i0': 'd74050897fbc9e6d',
		's1.b0.i1': '2d151dfb1f62d0b0',
		's1.b0.i2': 'aee700bc763c5ade',
		's1.b0.i3': '3222de96fadf77f6',
		's1.b1': '1ca4fbd7f7608965',
		's2.heading': '7e87e01018106f7c',
		's2.b0': '83dbaf9e7ca920df',
		's2.b1': '1195e880106739dc',
	},
};
