import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'follow-a-race-live',
	source: 'e0211e5c39173f51',
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
						'El nombre real de un corredor solo se muestra a las personas conectadas con él por un seguimiento, en cualquier dirección. Los demás ven un alias anónimo, como Runner #A1B2.',
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
};
