import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'import-your-history',
	title: 'Importar tu historial de carreras',
	summary: 'Trae tus carreras anteriores desde Strava, una exportación de Garmin o la app de salud de tu móvil, y descubre qué pasa con los archivos GPX.',
	sections: [
		{
			heading: 'Conectar Strava para tus carreras recientes y nuevas',
			blocks: [
				{
					type: 'steps',
					items: [
						'En la web, abre [[route:/settings/integrations|Integraciones]] en Configuración y selecciona **Conectar** en la tarjeta de Strava; en la app del móvil, abre **Integraciones** en la pestaña **Tú** y toca Strava.',
						'Inicia sesión en Strava y permite el acceso.',
						'Se copian tus carreras, caminatas y excursiones de los últimos 90 días, y las nuevas actividades de Strava llegan automáticamente.',
					],
				},
				{
					type: 'p',
					text: 'Selecciona **Sincronizar ahora** para volver a traerlas. En la web, **Hasta cuándo sincronizar** llega hasta un año atrás.',
				},
			],
		},
		{
			heading: 'Traer todo tu archivo de Strava',
			blocks: [
				{
					type: 'p',
					text: 'Conectar Strava solo alcanza la actividad reciente. Para años de historial, usa una exportación de datos de Strava.',
				},
				{
					type: 'steps',
					items: [
						'En Strava, ve a Ajustes, Mi cuenta, y solicita tu archivo. Strava te envía por correo un enlace a un archivo zip.',
						'En la web, abre [[route:/settings/integrations|Integraciones]], busca **Importación masiva desde una exportación de Strava** y selecciona **Elegir zip de exportación de Strava**. En la app del móvil, abre **Cuenta** en la pestaña **Tú**, luego **Importar desde otra app**, y toca **Importar ZIP de Strava**.',
						'Espera a que termine la importación. Las carreras que ya tienes, por ejemplo las de tu conexión con Strava, se omiten, así que puedes repetirla sin problema.',
					],
				},
			],
		},
		{
			heading: 'Garmin y archivos FIT',
			blocks: [
				{
					type: 'p',
					text: 'Todavía no hay una conexión automática con Garmin Connect porque Garmin tiene que aprobarla. Mientras tanto, puedes importar archivos de Garmin en la web.',
				},
				{
					type: 'steps',
					items: [
						'En Garmin Connect, exporta una actividad con Exportar original, que te da un archivo .fit, o solicita la exportación completa de tus datos desde la gestión de la cuenta de Garmin.',
						'En la web, abre [[route:/settings/integrations|Integraciones]], busca **Importación masiva desde una exportación de Garmin** y selecciona **Elegir exportación de Garmin**.',
						'Elige el archivo .fit o el zip. Las actividades que ya importaste se omiten.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'En Android, los entrenamientos que tu app de Garmin, Samsung o Fitbit escribe en Health Connect también pueden entrar a través de **Importar desde otra app**. En un iPhone, esa misma tarjeta lee Apple Salud.',
				},
			],
		},
		{
			heading: 'GPX y otros archivos sueltos',
			blocks: [
				{
					type: 'p',
					text: 'Un archivo GPX, KML, KMZ, GeoJSON o TCX suelto se importa como una ruta que puedes seguir, no como una carrera de tu historial. Abre [[route:/routes|Rutas]] en la web o la lista de rutas en la app e impórtalo allí.',
				},
				{
					type: 'p',
					text: 'Los archivos GPX y TCX que vienen dentro de un zip de exportación de Strava o Garmin se leen como carreras, así que las importaciones masivas de arriba son la forma de añadir un historial de actividades GPX.',
				},
			],
		},
		{
			heading: 'Si algo no se importa',
			blocks: [
				{
					type: 'p',
					text: 'Cuando se quedan fuera algunas actividades, la importación enumera cada una y el motivo, como una conexión perdida o un archivo que no se pudo leer. Vuelve a lanzar la importación para reintentarlas: lo que ya entró se omite, así que nada se duplica.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Las carreras importadas siguen tu privacidad predeterminada de las carreras, así que revísala antes de una importación grande si no quieres que años de carreras aparezcan en público de golpe. Consulta [[guide:your-data-and-privacy|Tus datos y tu privacidad]].',
				},
			],
		},
	],
	sources: {
		title: '078b29389d32808d',
		summary: '440ddd94eca0b542',
		's0.heading': '69858eb69781e59e',
		's0.b0.i0': '92767a2a2bf7c191',
		's0.b0.i1': '8c05e0ad16ddb8c2',
		's0.b0.i2': '828e8880f5239f1c',
		's0.b1': '4302ec5e7767e8ab',
		's1.heading': '8abf228027d2a4fd',
		's1.b0': 'cf7faaa4679e66f2',
		's1.b1.i0': '9e771e203c299ace',
		's1.b1.i1': 'a6d02ee139faa051',
		's1.b1.i2': '0212bc406356fd62',
		's2.heading': 'f3f586814898940a',
		's2.b0': '25c859eb00073fae',
		's2.b1.i0': 'f82bc798e8ec1b4e',
		's2.b1.i1': '21d706b389df8c6a',
		's2.b1.i2': '69a212e6bb305cfc',
		's2.b2': '7d501c5e8de3d96e',
		's3.heading': '8b42dffcf7f0d635',
		's3.b0': '0dba61c98d441dad',
		's3.b1': '5dbef244bd55926e',
		's4.heading': '35509c7701b9dabc',
		's4.b0': '26a0daac64b29af6',
		's4.b1': '69e6cfdbe0110cea',
	},
};
