import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'private-profile-and-follow-requests',
	title: 'Haz tu perfil privado y aprueba seguidores',
	summary: 'Activa un perfil privado para que solo los seguidores que apruebes vean tus carreras, y aprueba o rechaza las solicitudes de seguimiento según lleguen.',
	sections: [
		{
			heading: 'Qué oculta un perfil privado',
			blocks: [
				{
					type: 'p',
					text: 'Con un perfil privado, solo los seguidores que has aprobado ven tus carreras y otras actividades, y las listas de quién te sigue y a quién sigues. Los demás ven tu nombre, tu foto y tus cifras de seguidores, con **Este perfil es privado** donde estarían tus carreras.',
				},
				{
					type: 'list',
					items: [
						'Aun así pueden encontrarte por tu nombre y pedir seguirte. Para no aparecer tampoco en la búsqueda por nombre, desactiva **Mostrarme en la búsqueda por nombre** en la misma página.',
						'Quien ya te sigue cuando lo activas sigue siéndolo.',
						'Las rutas, los resultados de eventos y las insignias mantienen su propia visibilidad, porque cada uno se comparte por separado.',
						'Un enlace en directo que envíes durante una carrera, incluido el de una alerta de seguridad, sigue funcionando para quienes lo reciben.',
					],
				},
			],
		},
		{
			heading: 'Actívalo',
			blocks: [
				{
					type: 'steps',
					items: [
						'En la web, abre [[route:/settings/privacy|Privacidad y uso compartido]] en Configuración y marca **Perfil privado** en **Que te encuentren**.',
						'En la app móvil, abre **Preferencias** en la pestaña **Tú** y activa **Perfil privado** en **Privacidad y uso compartido**.',
					],
				},
				{
					type: 'p',
					text: 'El cambio se guarda al momento.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Si lo vuelves a desactivar, se aprueban todas las solicitudes pendientes y esas personas empiezan a seguirte de inmediato.',
				},
			],
		},
		{
			heading: 'Aprobar o rechazar solicitudes',
			blocks: [
				{
					type: 'p',
					text: 'Cuando alguien pide seguirte, recibes una notificación. Las solicitudes de seguimiento cuentan como importantes, así que por defecto también te llegan por correo y como notificación push.',
				},
				{
					type: 'steps',
					items: [
						'Abre la notificación. También puedes seleccionar **Ver solicitudes de seguimiento** en **Perfil privado** en la web, o tocar **Solicitudes de seguimiento** en **Perfil privado** en la app móvil.',
						'Elige **Aprobar** para que esa persona vea tu perfil, o **Rechazar** para denegar la solicitud. No se le avisa cuando la rechazas.',
					],
				},
			],
		},
		{
			heading: 'Seguir a alguien con perfil privado',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre su perfil y elige **Solicitar seguir**.',
						'Mientras esperas, el botón muestra **Solicitado**. Vuelve a elegirlo para retirar la solicitud.',
						'Cuando la aprueben, el botón muestra **Siguiendo** y aparecen sus carreras.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si dejas de seguir a alguien con perfil privado, tendrás que volver a pedirlo para ver sus carreras.',
				},
			],
		},
	],
	sources: {
		title: '55db0776dec72032',
		summary: 'e6bdb709c41db3db',
		's0.heading': '7237eeb5591555f6',
		's0.b0': '7c2c985869ef044e',
		's0.b1.i0': '46be0ce6681dea88',
		's0.b1.i1': 'a724eac62d2e2309',
		's0.b1.i2': 'ab64bd2163f3b938',
		's0.b1.i3': '3b0697b82ce30a11',
		's1.heading': 'e679ca0953315c31',
		's1.b0.i0': '8f81f66ef4f33b7f',
		's1.b0.i1': 'a2257970d4c18f57',
		's1.b1': '0a095b7bf566bcfd',
		's1.b2': 'ad288ebf5f9c8856',
		's2.heading': '93f13a5ed9bf1a93',
		's2.b0': 'd2a27163d9554bb2',
		's2.b1.i0': '2ed84578bbbb7b5f',
		's2.b1.i1': '6d2ff83c41b08bdc',
		's3.heading': '185850fe604d3b78',
		's3.b0.i0': 'd39f871565375e15',
		's3.b0.i1': 'd9de093774b97d75',
		's3.b0.i2': 'e44b708377c7377a',
		's3.b1': '6f8889c46cf20f3c',
	},
};
