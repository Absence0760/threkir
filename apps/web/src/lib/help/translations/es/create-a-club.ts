import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'create-a-club',
	source: 'eb2c9f65431381b4',
	title: 'Crear un club',
	summary: 'Crea un club para tu grupo de running, decide quién puede encontrarlo y cómo se une la gente, y publica tu primer evento.',
	sections: [
		{
			heading: 'En la web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre [[route:/social|Social]] y elige la pestaña **Clubes**.',
						'Selecciona **Crear club**.',
						'Rellena el **Nombre**. Los miembros buscan el club por este nombre, y la dirección web del club se genera a partir de él al crearlo. Cambiar el nombre del club más adelante no cambia esa dirección.',
						'Añade una **Descripción** y una **Ubicación** si quieres. Las dos son opcionales, pero una ciudad y un país en **Ubicación** ayudan a los corredores cercanos a encontrarte cuando buscan en su propia zona.',
						'Elige una **Visibilidad**: con **Público**, el club aparece en **Explorar**; con **Privado**, queda oculto y solo se puede entrar en él con un enlace de invitación.',
						'En **¿Quién puede unirse?**, elige **Cualquiera puede unirse**, **Requiere aprobación** o **Solo por invitación**.',
						'Marca **Exigir un reconocimiento de los riesgos de la actividad para unirse** si quieres que cada nuevo miembro confirme que entiende los riesgos de las salidas en grupo. Solo se puede configurar ahora, mientras se crea el club.',
						'Selecciona **Crear club**. Se te lleva a la página del nuevo club, y tú eres su propietario.',
					],
				},
			],
		},
		{
			heading: 'En la app del móvil',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre la pestaña **Social** y elige **Clubes**.',
						'Toca **Nuevo club**.',
						'Introduce un **Nombre** y, si quieres, una **Descripción (opcional)** y una **Ubicación (opcional)**.',
						'Elige **Público** o **Privado** y luego una **Política de ingreso**: **Abierto: cualquiera se une**, **Solicitud: los administradores aprueban** o **Solo por invitación**.',
						'Toca **Crear**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'El reconocimiento de los riesgos de la actividad y la web y los enlaces a redes sociales del club solo se pueden configurar en la web.',
				},
			],
		},
		{
			heading: 'Después de crearlo',
			blocks: [
				{
					type: 'p',
					text: 'La página de tu club tiene pestañas de **Feed**, **Eventos**, **Rutas**, **Plantillas**, **Fotos** y **Miembros**. Como propietario puedes publicar novedades en el feed, añadir eventos y gestionar a los miembros.',
				},
				{
					type: 'list',
					items: [
						'Para cambiar más adelante el nombre, la descripción, la visibilidad, la política de ingreso o los enlaces, abre el club en la web y selecciona **Editar club**.',
						'Para añadir tu primera salida en grupo, selecciona **Nuevo evento** en la web, o toca **Crear evento** en la pestaña **Eventos** de la app del móvil.',
						'Para traer gente, consulta [[guide:invite-members-and-roles|Invitar a miembros y asignarles roles]].',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Eliminar un club borra todos sus eventos, publicaciones y miembros para todo el mundo, y no se puede deshacer.',
				},
			],
		},
	],
};
