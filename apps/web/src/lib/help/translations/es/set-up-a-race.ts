import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'set-up-a-race',
	title: 'Organizar una carrera',
	summary: 'Crea un evento de club con uno o varios recorridos para que los corredores elijan una distancia, se les cronometre en directo y aparezcan en una clasificación por recorrido.',
	sections: [
		{
			heading: 'Antes de empezar',
			blocks: [
				{
					type: 'p',
					text: 'Una carrera es un evento de club normal con recorridos asociados. Los propietarios, los administradores y los organizadores de eventos del club pueden crear eventos. Dirigir la carrera el día (preparar, dar la salida, finalizar) requiere un propietario, un administrador o un **Director de carrera**: consulta [[guide:race-day-for-hosts|El día de la carrera para organizadores]].',
				},
				{
					type: 'p',
					text: 'Los recorridos se crean en la web. La app del móvil puede crear un evento sencillo, pero no tiene editor de recorridos, así que añade o cambia los recorridos desde un navegador.',
				},
			],
		},
		{
			heading: 'Crear el evento',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre tu club y elige **Nuevo evento**.',
						'En **Tipo de evento**, elige **Salida en grupo** (o **Ciclismo**). Los eventos de clase y sociales no tienen ruta, distancia, controles de carrera ni resultados.',
						'Ponle un **Título** y una **Fecha**. Configura una repetición solo si la carrera de verdad se repite; cada ocurrencia se corre por separado.',
						'Elige una **Ruta** y rellena la **Distancia**. Juntas forman tu *recorrido principal*.',
						'Si quieres, escribe un **Nombre del recorrido principal** en **Recorridos de la carrera** (por ejemplo, «Media maratón»). Si lo dejas en blanco, se usa el nombre de la ruta.',
						'Elige **Crear evento**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'La línea de meta en la que se cronometra a los corredores es el último punto de la ruta del recorrido. Dibuja la ruta para que termine exactamente donde estará tu arco de meta.',
				},
			],
		},
		{
			heading: 'Añadir más recorridos',
			blocks: [
				{
					type: 'p',
					text: '¿Se corre más de una distancia el mismo día? Añade cada distancia extra como su propio recorrido. Cada recorrido tiene su propia clasificación.',
				},
				{
					type: 'steps',
					items: [
						'En el editor del evento, busca **Recorridos de la carrera** y elige **Añadir un recorrido**.',
						'Ponle un **Nombre del recorrido**, elige su **Ruta** e introduce su distancia.',
						'Usa las flechas arriba y abajo para reordenar los recorridos, o quita uno que ya no necesites.',
						'Guarda el evento.',
					],
				},
				{
					type: 'list',
					items: [
						'Cada recorrido necesita un nombre, y dos recorridos no pueden compartirlo.',
						'Un recorrido sin ruta no tiene punto de meta, así que su llegada no se registra automáticamente; los corredores terminan a mano desde su dispositivo.',
						'Un recorrido sin distancia no puede comprobar que un corredor haya cubierto la mayor parte del recorrido, así que sus corredores también terminan a mano.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Al asociar una ruta, su punto de meta se muestra a todos los que pueden ver el evento, aunque la ruta en sí sea privada. Solo puedes asociar rutas que tienes permiso para ver.',
				},
			],
		},
		{
			heading: 'Qué ven los corredores',
			blocks: [
				{
					type: 'list',
					items: [
						'En la página del evento, los corredores ven los recorridos. Cuando hay más de uno, tienen que elegir uno en **Tu recorrido** para que **Me apunto** funcione; si no, ven «Elige tu recorrido primero.»',
						'En la app del móvil, al tocar **Voy** en una carrera con varios recorridos se les pide **Elige tu recorrido**, y más tarde pueden usar **Cambiar recorrido**.',
						'Con un único recorrido, nadie tiene que elegir nada.',
						'Las inscripciones de pago todavía no piden un recorrido. Un corredor que ha pagado elige uno después desde el mismo menú **Tu recorrido**.',
					],
				},
				{
					type: 'p',
					text: 'La parte de los corredores se explica en [[guide:racing-in-a-race|Competir en una carrera en directo]].',
				},
			],
		},
		{
			heading: 'Aprobar resultados automáticamente',
			blocks: [
				{
					type: 'p',
					text: 'Justo antes de preparar la carrera eliges si los resultados pasan directamente a la clasificación. **Aprobar automáticamente los resultados enviados** está marcada por defecto. Desmárcala si quieres revisar cada resultado primero; cada uno se muestra entonces como **PENDIENTE** hasta que lo apruebes.',
				},
			],
		},
		{
			heading: 'Compartir el enlace para espectadores',
			blocks: [
				{
					type: 'p',
					text: 'Cada ocurrencia de la carrera tiene una página en directo con un mapa y paneles. En la página del evento, la tarjeta de control de carrera tiene un enlace **Vista de espectador** que la abre en una pestaña nueva. Copia esa dirección y compártela con familia, amigos y el canal de tu carrera.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'En un evento **Solo para miembros**, solo los miembros del club pueden ver el evento, así que la página de espectadores no funcionará para personas de fuera del club.',
				},
				{
					type: 'p',
					text: 'Lo que ven los espectadores se explica en [[guide:follow-a-race-live|Seguir una carrera en directo]].',
				},
			],
		},
	],
	sources: {
		title: '9c550364ef27a6b1',
		summary: '366fcefd4c4d302c',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': 'e59685e187f9a957',
		's0.b1': '6109c712395ba1b9',
		's1.heading': 'bdd2bbbddd9c3cf5',
		's1.b0.i0': 'ad4d295ffcc8f3a0',
		's1.b0.i1': '6f2498dc63953e9d',
		's1.b0.i2': '1de2284a85b9b8d0',
		's1.b0.i3': '66dae8991279459e',
		's1.b0.i4': '5dc3211a9d733e18',
		's1.b0.i5': '9b013cf91adfef1d',
		's1.b1': '4dedb854832fabbb',
		's2.heading': 'aa02687fee3b093f',
		's2.b0': '1e44be9c1cbe6aa5',
		's2.b1.i0': '59ec7388c26ff153',
		's2.b1.i1': '7e55782eb49cd9f2',
		's2.b1.i2': 'b71f0dd3bc7d65dd',
		's2.b1.i3': 'e70bf0579a469363',
		's2.b2.i0': 'd37d68f01d59d140',
		's2.b2.i1': '614d8a4a47ff46c0',
		's2.b2.i2': '6ba6f0661b9e166a',
		's2.b3': '47950903add3bde2',
		's3.heading': '8b4ed9e415e501f7',
		's3.b0.i0': '7366e2c6f9eafeb3',
		's3.b0.i1': '76dc29eb1e584662',
		's3.b0.i2': '295fb740c0b19c57',
		's3.b0.i3': 'f12d86e7aff3dc0e',
		's3.b1': 'd636d4186f153c0f',
		's4.heading': 'ff04ee128bd05b1f',
		's4.b0': '8887aff2546f155b',
		's5.heading': '05127d2bcbe7e55c',
		's5.b0': '632ca275dd6dbc2e',
		's5.b1': 'd81f08a86fd29b85',
		's5.b2': '7375e2668380d4e1',
	},
};
