import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'create-a-club',
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
		{
			heading: 'Traer un club desde Strava',
			blocks: [
				{
					type: 'p',
					text: 'Si tu cuenta de Strava está conectada, abre [[route:/social|Social]] en la web, elige **Clubes** y luego **Mis clubes**. En **Tus clubes de Strava** ves los clubes de Strava a los que perteneces. Solo tú ves esta lista.',
				},
				{
					type: 'list',
					items: [
						'**Crear en Threkir** abre el formulario de un club nuevo con su nombre y ubicación ya rellenos, y vincula los dos en cuanto creas el club.',
						'**Vincular a mi club** lo une a un club que ya gestionas aquí: elígelo en **¿Cuál de tus clubes es este?** y selecciona **Vincular**.',
						'**Desvincular** quita la conexión. Ninguno de los dos clubes cambia.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Solo un administrador del club en Strava puede vincularlo, y solo a un club del que sea propietario o administrador aquí. Si no aparece la sección, conecta primero Strava en [[route:/settings/integrations|Integraciones]], dentro de Configuración.',
				},
			],
		},
	],
	sources: {
		title: 'ff916040a4a088ae',
		summary: '90e58c1ce029b9f8',
		's0.heading': '1e1b85a2667ca4d5',
		's0.b0.i0': '81704e449355f8cb',
		's0.b0.i1': 'acfe56320dd5fa86',
		's0.b0.i2': '8f5ed6e368636764',
		's0.b0.i3': '0b33c70ca105f651',
		's0.b0.i4': 'ac21a20e9c83b3b8',
		's0.b0.i5': '7d3a8a5850778a1a',
		's0.b0.i6': '8a20a1b7087f8a35',
		's0.b0.i7': '019cb8b4c6074fbe',
		's1.heading': 'f21eaef94c685b5c',
		's1.b0.i0': 'ecd88baa3a8b6dfe',
		's1.b0.i1': 'fe76ba21da4f039b',
		's1.b0.i2': '2cc7185287318c16',
		's1.b0.i3': '4bd544b513ee23e9',
		's1.b0.i4': '42d0b5b43ab9db8b',
		's1.b1': '8cc57f936798f492',
		's2.heading': '6620415f4bf77118',
		's2.b0': 'a1a749aa3fcf7a85',
		's2.b1.i0': 'a21817fe350e546b',
		's2.b1.i1': '102566e11462e84f',
		's2.b1.i2': '83bc170018336efe',
		's2.b2': 'eb88a7323310e67e',
		's3.heading': '78e0de8618ff020a',
		's3.b0': '728fa56591eb888d',
		's3.b1.i0': '57a98843d18952a0',
		's3.b1.i1': '6866a373a29d0bdb',
		's3.b1.i2': 'afe5b3477e772c36',
		's3.b2': '0c5f0a91de4775f1',
	},
};
