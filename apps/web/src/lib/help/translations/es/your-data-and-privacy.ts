import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'your-data-and-privacy',
	source: '71682d547c6ae11d',
	title: 'Tus datos y tu privacidad',
	summary: 'Consulta qué pueden ver los demás, elige quién ve tus nuevas carreras, descarga todo lo que guardamos sobre ti y elimina tu cuenta.',
	sections: [
		{
			heading: 'Qué pueden ver los demás',
			blocks: [
				{
					type: 'list',
					items: [
						'Tu página de perfil, con tu nombre visible, tu foto, tus cifras de seguidores y tus carreras públicas, puede abrirla cualquiera que tenga su enlace.',
						'Las carreras que haces públicas aparecen en tu perfil y en el feed. Las carreras privadas solo las ves tú.',
						'Tu pertenencia a un club público, y todo lo que publiques en él, pueden verlo las personas que pueden ver el club.',
						'Mientras compartes un enlace en directo, cualquiera que tenga el enlace puede ver la carrera en curso.',
					],
				},
				{
					type: 'p',
					text: 'Las zonas de privacidad recortan el inicio y el final de tus trazas en todos los sitios donde otra persona las ve. Consulta [[guide:privacy-zones|Ocultar tu casa con zonas de privacidad]].',
				},
			],
		},
		{
			heading: 'Elegir quién ve tus nuevas carreras',
			blocks: [
				{
					type: 'steps',
					items: [
						'En la web, abre [[route:/settings/privacy|Privacidad y uso compartido]] en Configuración y elige una **Visibilidad predeterminada para nuevas carreras**. En la app móvil, es **Privacidad predeterminada de las carreras**, en **Preferencias** de la pestaña **Tú**.',
						'Para cambiar una sola carrera más tarde, ábrela y usa **Hacer pública** o **Hacer privada**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Solo **Público** hace que las nuevas carreras sean visibles para los demás. Las carreras aún no tienen una opción solo para seguidores, así que elegir seguidores como predeterminado mantiene privadas las nuevas carreras, y tus seguidores no las verán.',
				},
				{
					type: 'list',
					items: [
						'**Mostrarme en la búsqueda por nombre**: desactívalo para que tu cuenta no aparezca en las búsquedas por nombre. Cualquiera que tenga el enlace puede seguir abriendo tu perfil y tus carreras públicas.',
						'**Mostrarme en Corredores cerca**, donde se ofrece: desactivado de forma predeterminada. Si lo activas, los corredores cerca de la zona que indiques pueden encontrarte. Solo se guarda una zona aproximada, nunca tu ubicación en directo.',
					],
				},
			],
		},
		{
			heading: 'Descargar tus datos',
			blocks: [
				{
					type: 'p',
					text: 'En la web, abre **Cuenta** en Configuración. La app móvil tiene las mismas opciones en **Cuenta**, en la pestaña **Tú**.',
				},
				{
					type: 'list',
					items: [
						'**Descargar archivo completo de la cuenta** (en el móvil, **Exportación de la cuenta**): todo lo que guardamos sobre ti, incluidos los chats con el entrenador, los mensajes, las integraciones y los contactos de seguridad, en un único zip. Se genera en nuestro servidor, así que puedes cerrar la página y volver a por él. Una exportación terminada se conserva 7 días.',
						'**Descargar copia completa** (en el móvil, **Copia de seguridad completa**): todas las carreras con su traza GPS, además de tus rutas, tu perfil y tus preferencias, en un archivo que puedes restaurar más tarde con **Restaurar desde copia**.',
						'**Exportación en la nube (zip GPX)**: un archivo GPX por carrera, con frecuencia cardíaca, listo para importar en otras apps. Las cuentas gratuitas pueden exportar dos veces por hora; las cuentas Pro, ocho.',
						'**Exportar todas las carreras (CSV)** (en el móvil, **Exportar carreras como CSV**): una fila por carrera para una hoja de cálculo, sin trazas GPS.',
					],
				},
			],
		},
		{
			heading: 'Eliminar tu cuenta',
			blocks: [
				{
					type: 'steps',
					items: [
						'Descarga primero todo lo que quieras conservar. La eliminación no se puede deshacer.',
						'En la web, abre **Cuenta** en Configuración y selecciona **Eliminar cuenta** en **Zona de peligro**. En la app móvil, abre **Cuenta** en la pestaña **Tú** y toca **Eliminar cuenta**.',
						'Escribe ELIMINAR para confirmar y luego selecciona **Eliminar mi cuenta** en la web o **Eliminar** en la app.',
					],
				},
				{
					type: 'p',
					text: 'Esto elimina permanentemente de nuestros servidores tu cuenta, tus carreras, rutas, trazas, membresías de clubes y preferencias. En un móvil, las carreras guardadas en el propio dispositivo se quedan ahí hasta que inicies sesión con otra cuenta o elimines la app.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: '¿No puedes entrar en la app? [[route:/delete-account|Eliminar tu cuenta]] explica cómo solicitar la eliminación sin ella.',
				},
			],
		},
	],
};
