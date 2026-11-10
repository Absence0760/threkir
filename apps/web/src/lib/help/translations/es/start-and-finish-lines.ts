import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'start-and-finish-lines',
	title: 'Líneas de salida y meta',
	summary: 'Qué son las líneas de salida y meta de un recorrido, cómo se colocan automáticamente y cómo moverlas, girarlas, ensancharlas o colocarlas tú mismo.',
	sections: [
		{
			heading: 'Qué es una línea',
			blocks: [
				{
					type: 'p',
					text: 'Cada recorrido de una carrera tiene una línea de salida y una línea de meta. Una línea atraviesa el recorrido en un punto, está orientada en el sentido en que avanzan los corredores y se extiende una distancia fija a cada lado. Un corredor solo la cruza si pasa a través de ella en ese sentido y dentro de su alcance.',
				},
				{
					type: 'p',
					text: 'Esa es la diferencia con un punto de meta rodeado por un círculo de 30 m. Un círculo cuenta a cualquiera que se acerque: un corredor que va por un camino paralelo, o que está en la ida de un recorrido de ida y vuelta que regresa por el mismo camino. Una línea no los cuenta, porque nunca la cruzan en el sentido correcto.',
				},
			],
		},
		{
			heading: 'Líneas colocadas automáticamente',
			blocks: [
				{
					type: 'p',
					text: 'Cuando un recorrido tiene ruta, recibe de ella las dos líneas. La línea de salida está en el primer punto de la ruta, orientada a lo largo de la ruta. La línea de meta está en su último punto, orientada en el sentido en que llega la ruta. Cada una se extiende 15 m a cada lado. Siguen a la ruta: si cambias la ruta, se mueven con ella.',
				},
				{
					type: 'p',
					text: 'Las líneas aparecen en cuanto el evento se guarda con al menos un recorrido. Abre el evento, elige **Editar evento** y busca **Líneas de salida y meta**. Cada recorrido tiene un mapa y una fila por línea, que indica de dónde viene la línea: **De la ruta**, **Colocada por un organizador** o **Ninguna**.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si el propietario de la ruta tiene una zona de privacidad sobre el inicio o el final de la ruta, ese extremo queda oculto para todos los demás, así que no recibe línea. Coloca esa línea tú mismo.',
				},
			],
		},
		{
			heading: 'Mover, girar o ensanchar una línea',
			blocks: [
				{
					type: 'steps',
					items: [
						'Junto a **Línea de salida** o **Línea de meta**, elige **Editar**.',
						'En el mapa, arrastra el centro de la línea para moverla y arrastra su tirador para girarla. Si el mapa está desactivado, elige **Cargar mapa**, o prescinde del mapa y escribe los valores.',
						'O escribe la **Latitud**, la **Longitud** y la **Dirección (grados)**. La dirección es el sentido en que cruzan los corredores, en sentido horario desde el norte: 0 es norte, 90 este, 180 sur y 270 oeste.',
						'Ajusta el **Alcance a cada lado**, de 5 a 100 m. Hazlo lo bastante ancho para cubrir toda la carretera o el camino, y un poco más.',
						'Elige **Guardar la línea**.',
					],
				},
				{
					type: 'p',
					text: 'Cada línea se guarda por separado, al instante; no hace falta guardar el evento. Una línea que has movido muestra **Colocada por un organizador**. Elige **Restablecer a la ruta** para devolverla adonde la coloca la ruta.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Una línea que has colocado se queda exactamente donde la pusiste, aunque después cambies la ruta del recorrido. Después de cambiar una ruta, revisa los avisos que aparecen bajo cada línea.',
				},
			],
		},
		{
			heading: 'Avisos en el editor',
			blocks: [
				{
					type: 'list',
					items: [
						'La línea está a más de 100 m de la ruta del recorrido. Comprueba que esté en el lugar correcto.',
						'La línea apunta en contra de la ruta, así que quien siga la ruta la cruzaría al revés. Dale la vuelta.',
						'La ruta cruza su propia línea de meta antes del final, como hace un recorrido de vueltas o una pista. Entonces la llegada por la línea se desactiva en ese recorrido, y los corredores terminan pulsando Detener o Terminar.',
					],
				},
			],
		},
		{
			heading: 'Recorridos sin ruta',
			blocks: [
				{
					type: 'p',
					text: 'Un recorrido sin ruta no tiene líneas hasta que las colocas. Elige **Colocar la línea de salida** o **Colocar la línea de meta**. Si antes has movido el mapa hasta el lugar, la línea empieza en el centro del mapa; si no, escribe su posición. Después ajusta su dirección y su alcance y elige **Guardar la línea**. **Quitar la línea** elimina de nuevo una línea que hayas colocado.',
				},
			],
		},
		{
			heading: 'Las líneas se fijan cuando empieza una carrera',
			blocks: [
				{
					type: 'p',
					text: 'Cuando preparas una carrera (en una carrera con cronometraje propio, cuando se abre su ventana), las líneas de cada recorrido se copian para esa carrera. Así todos sus corredores cruzan las mismas líneas, cambie lo que cambie durante la carrera. Un cambio que hagas después se aplica desde la siguiente carrera. La página del evento y la página de carrera en directo muestran las líneas con las que se preparó la carrera.',
				},
			],
		},
		{
			heading: 'Comprobaciones antes de una carrera',
			blocks: [
				{
					type: 'p',
					text: 'Antes de preparar una carrera, se comprueban las líneas de todos los recorridos, en la web y en la app del móvil. Un aviso te deja elegir **Preparar de todos modos**; un problema marcado con **Hay que corregir:** impide preparar la carrera hasta que lo corrijas en el editor del evento en la web.',
				},
				{
					type: 'list',
					items: [
						'Un recorrido sin línea de meta ni punto de meta: un aviso, porque sus corredores terminan a mano. Una carrera con cronometraje propio tiene que corregirlo.',
						'Un recorrido sin línea de salida: una carrera con cronometraje propio tiene que corregirlo. Las demás carreras pueden empezar sin ella.',
						'Una ruta que cruza su propia línea de meta antes del final: un aviso, porque la llegada por la línea está desactivada en ese recorrido. Una carrera con cronometraje propio tiene que corregirlo.',
						'Una línea a más de 100 m de la ruta: un aviso en cualquier tipo de carrera.',
					],
				},
				{
					type: 'p',
					text: 'El tipo de carrera que organizas se elige en **Cómo empieza la carrera**; consulta [[guide:choose-how-your-race-starts|Elegir cómo empieza tu carrera]].',
				},
			],
		},
	],
	sources: {
		title: 'e32b975b30a0bfdf',
		summary: '007484d24c448df5',
		's0.heading': 'b2178bb9e4c07f85',
		's0.b0': '7b22e9bee9ea6e44',
		's0.b1': 'e18c2ba36732dafb',
		's1.heading': '6ae01aac1742fa11',
		's1.b0': '98879a39846cccd2',
		's1.b1': '1121c7b877f6a658',
		's1.b2': '5d09b8607f6a2f22',
		's2.heading': 'b839a49fc88eb9bb',
		's2.b0.i0': 'f9a4dd08d366b730',
		's2.b0.i1': '0bfc28ecb00a6d5b',
		's2.b0.i2': '29eaf88dee6df1d8',
		's2.b0.i3': '082f59f63580a00b',
		's2.b0.i4': '008936c6ea875617',
		's2.b1': 'e6292e6047487d65',
		's2.b2': '5bad76f945b81e03',
		's3.heading': '49bbc9db5d4c7163',
		's3.b0.i0': 'c519f8cea9bd87d0',
		's3.b0.i1': 'e08a656a24f1ed58',
		's3.b0.i2': 'aa848004795cf7a1',
		's4.heading': '3bd16f8003e613ef',
		's4.b0': 'adfbcab88a7c3e90',
		's5.heading': 'be581f997710aa1d',
		's5.b0': 'b691f01dae47a921',
		's6.heading': 'a1cbd797f4858538',
		's6.b0': '3ab85eab34b17f4c',
		's6.b1.i0': 'e5b89e5070aad84a',
		's6.b1.i1': '2d67c55e24d207a9',
		's6.b1.i2': '1ecbd8a36af71c78',
		's6.b1.i3': '84f19ca583307307',
		's6.b2': 'cfbf64534e49a993',
	},
};
