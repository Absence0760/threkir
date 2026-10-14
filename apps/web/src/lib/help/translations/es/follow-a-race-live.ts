import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'follow-a-race-live',
	title: 'Seguir una carrera en directo',
	summary: 'Sigue una carrera mientras sucede en la página de carrera en directo: los corredores en un mapa, quién está en carrera y quién ha terminado en cada recorrido.',
	sections: [
		{
			heading: 'Abrir la página en directo',
			blocks: [
				{
					type: 'p',
					text: 'El organizador comparte un enlace a la página de carrera en directo o, si puedes ver el evento, ábrelo y elige **Vista de espectador**. No necesitas cuenta. Si el evento es **Solo miembros**, tienes que ser miembro del club para verlo.',
				},
				{
					type: 'p',
					text: 'La parte superior de la página muestra el estado de la carrera:',
				},
				{
					type: 'list',
					items: [
						'**Antes de la carrera**: el organizador todavía no ha preparado el cronómetro de la carrera.',
						'**Listo**: el cronómetro está preparado y esperando la salida.',
						'**En curso**: la carrera está en marcha, con el tiempo transcurrido.',
						'**Finalizado**: la carrera ha terminado.',
						'**Cancelado**: el organizador ha cancelado la carrera.',
					],
				},
			],
		},
		{
			heading: 'El mapa',
			blocks: [
				{
					type: 'p',
					text: 'Salvo que ya hayas permitido los mapas en tus ajustes de cookies, el mapa permanece desactivado hasta que elijas **Cargar mapa**, porque al cargarlo se envía tu dirección IP a nuestro proveedor de teselas de mapa. Una vez cargado, cada corredor es un punto de color con una estela corta de su recorrido reciente. Los móviles y relojes de los corredores envían una posición aproximadamente cada 10 segundos, y la página se actualiza sola.',
				},
				{
					type: 'illustration',
					id: 'follow-a-race-live',
					alt: 'Un recorrido en un mapa con corredores, cada uno un punto de color con un breve rastro de su trayecto reciente, y una bandera en la meta.',
				},
			],
		},
		{
			heading: 'En carrera',
			blocks: [
				{
					type: 'p',
					text: 'El panel **En carrera** muestra a todos los corredores que han enviado una posición, del más adelantado al más retrasado, con distancia, ritmo y tiempo transcurrido, con un panel por recorrido cuando la carrera tiene más de uno. Cada fila indica también hace cuánto se actualizó por última vez.',
				},
				{
					type: 'p',
					text: 'No hay una etiqueta aparte de «en pausa». Un corredor que se ha detenido (para atarse un cordón, en un avituallamiento o porque ha pausado su grabación) o que ha perdido la señal simplemente deja de actualizarse. Tras unos 90 segundos sin actualización, su fila se marca como **RETRASADO**. Eso no significa que pase algo malo; a menudo solo indica que no hay señal.',
				},
			],
		},
		{
			heading: 'Llegadas',
			blocks: [
				{
					type: 'p',
					text: 'Quienes terminan aparecen en **Finalizado** a medida que llegan sus resultados, con un panel por recorrido cuando la carrera tiene más de uno. Los corredores que no terminaron aparecen en **No finalizó**. Un resultado que el organizador aún no ha aprobado se marca como **Pendiente**.',
				},
				{
					type: 'p',
					text: 'Qué significan los tiempos y las insignias se explica en [[guide:race-results-explained|Los resultados de carrera, explicados]].',
				},
			],
		},
		{
			heading: 'Privacidad',
			blocks: [
				{
					type: 'list',
					items: [
						'El nombre real de un corredor solo se muestra a las personas conectadas con él por un seguimiento, en cualquier dirección. Los demás ven un alias anónimo, como Corredor #A1B2.',
						'Cerca de la zona de privacidad de un corredor, su posición exacta se oculta. En su lugar ves **Visto por última vez cerca de aquí · aproximado**, representado con un anillo hueco en vez de un punto.',
						'Los corredores que el organizador importa desde una lista de dorsales no tienen cuenta, así que conservan el nombre que introdujo el organizador.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Cualquiera con el enlace puede seguir la carrera. Si vas a correr y prefieres que no te sigan en directo, habla con el organizador antes de la carrera.',
				},
			],
		},
	],
	sources: {
		title: '2c62c5274378a304',
		summary: '6907f1876e7b883e',
		's0.heading': '9e53c8e8fdd29829',
		's0.b0': '386a683bed4bd1dd',
		's0.b1': 'c2d62153581d81fa',
		's0.b2.i0': '3a6d56e541fe4565',
		's0.b2.i1': 'c3dd12cae69c5cf5',
		's0.b2.i2': '120d1d8d969ced75',
		's0.b2.i3': 'fbe2e397efb8ef5e',
		's0.b2.i4': '1709d9ad712d85d2',
		's1.heading': 'dc711bb38f5066a7',
		's1.b0': 'f40d0503826f0955',
		's2.heading': '46db515d7f1689a7',
		's2.b0': '3316e288511685d1',
		's2.b1': 'cff7f7798a6785c9',
		's3.heading': '7804f7a79a9eee32',
		's3.b0': '4355700d3a60d89c',
		's3.b1': 'ea613ba62f6ba84a',
		's4.heading': '54a57c3147c49f33',
		's4.b0.i0': 'b8c1ad08a0dc3387',
		's4.b0.i1': '7cf40c647db03cc3',
		's4.b0.i2': 'edbbe7f08d1cf63e',
		's4.b1': '1bb7132a7305e850',
		's1.b1': '1afba2a8fcb03c42',
	},
};
