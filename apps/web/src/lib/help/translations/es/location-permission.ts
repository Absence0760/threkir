import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'location-permission',
	title: 'Acceso a la ubicación para registrar carreras',
	summary: 'Qué opción de ubicación elegir en Android y en iPhone, qué supone cada una para tus carreras y cómo cambiarla más adelante en los ajustes.',
	sections: [
		{
			heading: 'Por qué la app pide tu ubicación',
			blocks: [
				{
					type: 'p',
					text: 'Tu ubicación dibuja el mapa de una carrera y mide su distancia y su ritmo. Sin ella, una carrera sigue registrando tiempo y pasos, pero sin mapa, distancia ni ritmo.',
				},
				{
					type: 'p',
					text: 'Se te pregunta durante la configuración: después de la página **Acceso a la ubicación**, al tocar **Conceder permiso** se abre la solicitud de tu teléfono. Si la rechazas, la app te lo indica y te ofrece **Abrir ajustes**. Si aún no lo has permitido cuando tocas **INICIAR**, puede que tu teléfono vuelva a preguntar.',
				},
			],
		},
		{
			heading: 'En Android',
			blocks: [
				{
					type: 'p',
					text: 'La primera solicitud de Android solo puede dar acceso mientras usas la app. Para que la carrera se siga registrando con la pantalla apagada hace falta **Permitir todo el tiempo**, y Android solo deja elegirlo en los ajustes.',
				},
				{
					type: 'steps',
					items: [
						'En la solicitud, deja seleccionada **Precisa** y toca **Mientras la aplicación está en uso**.',
						'Antes de tu primera carrera, la app muestra **Permitir la ubicación todo el tiempo**. Toca **Abrir ajustes**.',
						'En **Permisos**, toca **Ubicación**, elige **Permitir todo el tiempo** y vuelve a la app.',
					],
				},
				{
					type: 'p',
					text: 'Si tocas **Iniciar de todos modos**, la carrera se registra con normalidad mientras la app está en pantalla. Con la pantalla apagada o en otra app, Android puede dejar de enviar tu ubicación: el reloj sigue corriendo y no se pierde nada de lo ya registrado, pero la distancia que recorres mientras tanto no se cuenta. Cuando ocurre, al volver aparece un mensaje que empieza por **El seguimiento se pausó mientras no estabas**, con un botón **Ajustes**.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'El aviso antes de una carrera aparece una sola vez. Solo vuelve si habías permitido el acceso todo el tiempo y después se retiró, por ejemplo porque Android restablece los permisos de las apps que no abres desde hace tiempo.',
				},
				{
					type: 'list',
					items: [
						'Con **Aproximada**, la ubicación es demasiado imprecisa para medir una carrera: verás **GPS débil — distancia en pausa** durante toda la carrera.',
						'**Solo esta vez** sirve para la carrera que vas a empezar, y la próxima vez se te vuelve a preguntar.',
						'Con **No permitir**, las carreras solo registran tiempo y pasos.',
					],
				},
			],
		},
		{
			heading: 'En iPhone',
			blocks: [
				{
					type: 'p',
					text: 'En iPhone basta con el acceso mientras usas la app: una carrera sigue registrándose con la pantalla bloqueada o mientras usas otra app. La app nunca pide **Siempre**, y no lo necesitas.',
				},
				{
					type: 'steps',
					items: [
						'En la solicitud, toca **Permitir al usar la app**.',
						'Deja activada la ubicación exacta en la solicitud. Sin ella, tu posición es demasiado imprecisa para medir la distancia, y la carrera muestra **GPS débil — distancia en pausa**.',
					],
				},
				{
					type: 'p',
					text: '**Permitir una vez** sirve solo para esta carrera, y la próxima vez se te vuelve a preguntar. Con **No permitir**, las carreras solo registran tiempo y pasos.',
				},
			],
		},
		{
			heading: 'Ahorro de batería',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Algunos teléfonos Android (Samsung, Xiaomi, OnePlus y otros) suspenden las apps para ahorrar batería, lo que puede detener el registro de una carrera larga con la pantalla apagada, incluso con **Permitir todo el tiempo**. Antes de tu primera carrera, la app muestra una vez **Mantener la grabación activa en segundo plano**: toca **Abrir ajustes** y excluye Threkir de la optimización de batería. Si tocaste **Ahora no**, abre la página de la app en los ajustes de tu teléfono, toca **Batería** y elige **Sin restricciones**. Los nombres cambian un poco según el fabricante.',
				},
			],
		},
		{
			heading: 'Cambiarlo más adelante',
			blocks: [
				{
					type: 'p',
					text: 'En Android:',
				},
				{
					type: 'steps',
					items: [
						'Abre los **Ajustes** de tu teléfono y toca **Aplicaciones** y luego **Threkir**.',
						'Toca **Permisos** y luego **Ubicación**.',
						'Elige **Permitir todo el tiempo** y activa **Usar ubicación precisa**.',
					],
				},
				{
					type: 'p',
					text: 'En iPhone:',
				},
				{
					type: 'steps',
					items: [
						'Abre **Ajustes** › **Privacidad y seguridad** › **Localización** y comprueba que **Localización** está activada.',
						'Toca **Threkir** y elige **Cuando se use la app**.',
						'Activa **Ubicación exacta**.',
					],
				},
				{
					type: 'p',
					text: 'Si la ubicación está desactivada o bloqueada cuando empiezas una carrera, la pantalla de carrera te lo indica y su botón **Ajustes** te lleva al sitio adecuado.',
				},
			],
		},
		{
			heading: 'Qué hace la app con tu ubicación',
			blocks: [
				{
					type: 'list',
					items: [
						'La lee mientras registras una carrera y cuando un mapa se centra en ti, por ejemplo al crear una ruta o colocar una zona de privacidad. No te sigue entre carreras.',
						'En Android, una notificación se muestra mientras se registra una carrera, si permites las notificaciones.',
						'El recorrido de una carrera se queda en tu teléfono hasta que se sincroniza con tu cuenta o lo compartes, y quién puede verlo depende de tus ajustes de privacidad: consulta [[guide:your-data-and-privacy|tus datos y tu privacidad]].',
						'Para ocultar dónde vives, configura [[guide:privacy-zones|zonas de privacidad]]. Tu posición en directo solo se comparte si activas el [[guide:live-tracking-and-safety|seguimiento en directo]].',
					],
				},
			],
		},
	],
	sources: {
		'title': '583816a170012c19',
		'summary': '56769a6e224ff156',
		's0.heading': '794b04c19c7668d8',
		's0.b0': 'af2524b060ff7e41',
		's0.b1': 'c4efda4e34e087e7',
		's1.heading': 'd085d4c0606e9a65',
		's1.b0': 'f87947ee024ca95d',
		's1.b1.i0': '74eca884f8eb053b',
		's1.b1.i1': 'bc08250477141230',
		's1.b1.i2': 'cd926bc8428f270d',
		's1.b2': '3f9237c89f00534f',
		's1.b3': '6c15e5f41c0dbad5',
		's1.b4.i0': '96fb29287371ef73',
		's1.b4.i1': 'd35c46ecb6f1579e',
		's1.b4.i2': '09d7ce333fe83b8c',
		's2.heading': '873081b6807b4197',
		's2.b0': '6912b4c52f4c4037',
		's2.b1.i0': '302121c948975146',
		's2.b1.i1': '7bcc2b01bf8a35ab',
		's2.b2': 'dd5515e417bcce18',
		's3.heading': 'd91eca07ad12c491',
		's3.b0': '5ecc6e3ad1cacf65',
		's4.heading': '8489bd921c93cd06',
		's4.b0': '8a324e6ccca0ee87',
		's4.b1.i0': '682f9bd3caa2bb73',
		's4.b1.i1': '8cad8da0c6d30e3e',
		's4.b1.i2': '007cea366706e1e4',
		's4.b2': '1eb507e8f5d10b2b',
		's4.b3.i0': '29ad09bb32235340',
		's4.b3.i1': '54f8b50ec24d5250',
		's4.b3.i2': '4bbab96422f563b9',
		's4.b4': '20e869463ad7c51c',
		's5.heading': '11a805eb39c14582',
		's5.b0.i0': 'e4acbdfc462c84a6',
		's5.b0.i1': '1a49253f9adf5652',
		's5.b0.i2': '79d0adcf35c722c0',
		's5.b0.i3': 'f79c6d8e7f96a30f',
	},
};
