import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'set-up-a-race',
	source: '007da6d05532b4cb',
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
};
