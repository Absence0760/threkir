import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'notifications-reactions-and-mentions',
	title: 'Reacciones, menciones y tus notificaciones',
	summary: 'Reacciona a carreras, da me gusta a comentarios y menciona a otros corredores, y elige qué notificaciones te llegan también por correo y al móvil.',
	sections: [
		{
			heading: 'Reaccionar, dar me gusta y mencionar',
			blocks: [
				{
					type: 'list',
					items: [
						'En la carrera de otra persona, junto a los kudos, elige una reacción: **Imparable**, **Fuerte**, **Campeón**, **Bien hecho** u **Hola**. Puedes dejar más de una, y elegir otra vez una reacción la quita.',
						'Para dar me gusta a un comentario, elige el corazón que tiene al lado. No puedes reaccionar a tu propia carrera ni dar me gusta a tu propio comentario.',
						'Para mencionar a alguien en un comentario, escribe @ y el principio de su nombre, y elige a la persona en la lista que aparece. Solo se le avisa si ya puede ver la carrera y ninguno de los dos ha bloqueado al otro.',
					],
				},
				{
					type: 'p',
					text: 'Las reacciones y los me gusta en comentarios se ven en la propia carrera. Las tarjetas del feed siguen mostrando solo el número de kudos y de comentarios.',
				},
			],
		},
		{
			heading: 'Dónde aparecen las notificaciones',
			blocks: [
				{
					type: 'p',
					text: 'Todas las notificaciones llegan a la app: bajo la campana en la web, y en la pestaña **Notificaciones** de tu perfil en la app móvil. Tú decides si además te llegan por correo o al móvil.',
				},
			],
		},
		{
			heading: 'Elegir qué se envía por correo y push',
			blocks: [
				{
					type: 'steps',
					items: [
						'En la web, abre [[route:/settings/notifications|Notificaciones]] en Configuración. En la app móvil, abre **Preferencias** en la pestaña **Tú** y desplázate hasta **Notificaciones**.',
						'Ajusta **Notificaciones por correo** y **Notificaciones push** por separado.',
					],
				},
				{
					type: 'list',
					items: [
						'**Solo importantes**, la opción predeterminada: lo que estás esperando o lo que cambia tus planes, como mensajes, recordatorios y cancelaciones de eventos, una plaza reservada para ti en una lista de espera, menciones, solicitudes de seguimiento y una exportación de datos terminada.',
						'**Todas**: las importantes más las sociales, como kudos, comentarios, nuevos seguidores, reacciones y me gusta en comentarios.',
						'**Desactivadas**: nada por ese canal. La app sigue mostrándolo todo.',
					],
				},
			],
		},
		{
			heading: 'Desactivar un solo tipo',
			blocks: [
				{
					type: 'p',
					text: 'En la web, la misma página te deja silenciar algunos tipos sin cambiar todo un canal: **Exportación de datos lista**, **Menciones**, **Reacciones a mis carreras**, **Me gusta en mis comentarios** y **Solicitudes de seguimiento**. Desmarca uno y deja de enviarse por correo y push, también al móvil, pero sigue apareciendo en la app.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Estas casillas solo sirven para quitar. Las reacciones y los me gusta en comentarios solo se envían cuando un canal está en **Todas**, y un canal en **Desactivadas** no envía nada, digan lo que digan las casillas.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Por ahora, las casillas por tipo solo están en la web. La app móvil muestra los ajustes de correo y push.',
				},
			],
		},
	],
	sources: {
		title: 'e2dd210eef629161',
		summary: 'e3caa3dd4051e339',
		's0.heading': 'e9a0aa732a34f472',
		's0.b0.i0': '593bf97b7d4b2620',
		's0.b0.i1': '47c9a6dbdeb3921f',
		's0.b0.i2': '3f6f5a25189cef93',
		's0.b1': 'a9ec227602fcdf51',
		's1.heading': '074e9ceb824efc1f',
		's1.b0': '93884f29ad0c80fc',
		's2.heading': 'effb878df9e1a9ea',
		's2.b0.i0': '1c0dfd20d4a186e9',
		's2.b0.i1': '5a887c760fb14d6f',
		's2.b1.i0': '3adf3c1bbb3ad28d',
		's2.b1.i1': '20670a8e203c8f76',
		's2.b1.i2': '0e68d1c319340628',
		's3.heading': '99fb6c0af9167c4d',
		's3.b0': 'f6afa349950bc135',
		's3.b1': '17f7f798ca3f2b0d',
		's3.b2': '7471f8039fdd65e1',
	},
};
