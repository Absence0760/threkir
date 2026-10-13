import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-day-for-hosts',
	source: 'a0030f79feb5cc1b',
	title: 'El día de la carrera para organizadores',
	summary: 'Prepara la carrera, da la salida, síguela en directo, finalízala y después aprueba y corrige los resultados.',
	sections: [
		{
			heading: 'Quién puede dirigir una carrera',
			blocks: [
				{
					type: 'p',
					text: 'El control de carrera aparece en la página del evento para los propietarios y administradores del club y para los miembros con el rol de **Director de carrera**. En la web es la tarjeta **Control de carrera**; en la app del móvil es la tarjeta **CONTROL DE CARRERA** de la pantalla del evento. En ambas se pueden aprobar y editar resultados.',
				},
				{
					type: 'p',
					text: 'Asegúrate antes de que el evento tenga recorridos: consulta [[guide:set-up-a-race|Organizar una carrera]].',
				},
			],
		},
		{
			heading: '1. Preparar la carrera',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre el evento y, si se repite, elige la ocurrencia de hoy.',
						'Deja marcada **Aprobar automáticamente los resultados enviados** para publicar los resultados según llegan, o desmárcala para aprobar cada uno tú mismo. (En la app del móvil dice **Aprobar automáticamente los tiempos enviados**.)',
						'Elige **Preparar carrera** cuando estén todos reunidos.',
					],
				},
				{
					type: 'p',
					text: 'Los corredores que dijeron **Voy** ven ahora **Carrera lista** en la pestaña Correr de su móvil y «CARRERA LISTA» en su reloj Wear OS.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Preparada es un estado de espera. No se cronometra nada ni se pueden guardar resultados hasta que des la salida.',
				},
			],
		},
		{
			heading: '2. Dar la salida',
			blocks: [
				{
					type: 'p',
					text: 'Pulsa **YA** en la web (**Dar la salida** en la app del móvil) en el momento en que empieza la carrera.',
				},
				{
					type: 'p',
					text: 'La hora de salida la marca nuestro servidor, no tu dispositivo, así que es la misma hora de salida para todos los corredores aunque el reloj de tu móvil vaya unos segundos desfasado. El tiempo oficial de cada corredor se mide a partir de ella.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Dar la salida no inicia la grabación de nadie. Los corredores pulsan Iniciar en su propio móvil o reloj, ya sea en la línea de salida mientras la carrera está preparada (la grabación se une a la carrera en la salida) o después de ver **Carrera EN VIVO**. Recuérdales que inicien la grabación.',
				},
			],
		},
		{
			heading: '3. Seguirla en directo',
			blocks: [
				{
					type: 'list',
					items: [
						'La tarjeta de control de carrera muestra **En curso** con el tiempo transcurrido.',
						'Elige **Vista de espectador** para ver el mapa en directo, el panel **En carrera** y el panel **Finalizado**. Consulta [[guide:follow-a-race-live|Seguir una carrera en directo]].',
						'Los dispositivos de los corredores registran su llegada automáticamente en la línea de meta, así que los resultados aparecen en la página del evento mientras la carrera sigue en curso.',
					],
				},
			],
		},
		{
			heading: '4. Finalizar la carrera',
			blocks: [
				{
					type: 'steps',
					items: [
						'Cuando haya llegado el último corredor (o haya pasado tu hora de cierre), elige **Finalizar carrera**.',
						'La confirmación, en la web y en la app del móvil, te indica cuántos corredores que tomaron la salida no tienen resultado. Esos corredores se marcarán como DNF.',
						'Confirma con **Finalizar carrera**.',
					],
				},
				{
					type: 'p',
					text: 'Al finalizar, se registra un DNF para cada corredor que envió al menos una posición en directo pero no tiene resultado, con la distancia y el tiempo de su última posición. Estos DNF llevan la marca del organizador. A los corredores que nunca empezaron a grabar no se les registra nada.',
				},
				{
					type: 'p',
					text: 'Un corredor cuyo móvil o reloj estaba sin señal en la meta todavía puede enviar un resultado pendiente hasta 24 horas después de que finalices la carrera, y ese resultado sustituye al DNF.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Finalizar no se puede deshacer. Una vez finalizada, los dispositivos de los corredores dejan de esperar un resultado. Para volver a correr la misma ocurrencia, prepara una nueva sesión.',
				},
			],
		},
		{
			heading: 'Cancelar',
			blocks: [
				{
					type: 'p',
					text: 'Solo puedes cancelar mientras la carrera está preparada: elige **Cancelar** junto a **YA** (**Dar la salida** en la app del móvil) y luego **Cancelar carrera**. Una vez dada la salida, la carrera solo se puede finalizar.',
				},
				{
					type: 'p',
					text: 'Cancelar no registra ningún DNF. La página de espectadores indica que el organizador canceló la carrera, y los corredores ven que la carrera ha terminado.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Cancelar no se puede deshacer. Usa **Finalizar carrera** en su lugar si la gente llegó a correr y quieres sus resultados.',
				},
			],
		},
		{
			heading: 'Aprobar y editar los resultados',
			blocks: [
				{
					type: 'p',
					text: 'Los resultados están en la página del evento, en **Resultados**, con un panel por recorrido. En la app del móvil, cada resultado tiene un menú con las mismas acciones **Aprobar**, **Quitar verificación** y **Editar**.',
				},
				{
					type: 'list',
					items: [
						'Si la aprobación automática estaba desactivada, los resultados nuevos muestran **PENDIENTE** y ningún puesto. Elige **Aprobar** para publicar uno. **Quitar verificación** devuelve un resultado aprobado a pendiente.',
						'Para corregir un resultado, elige **Editar**, introduce un **Tiempo (h:mm:ss)** y un **Estado** (**Terminado**, **DNF** o **DNS**) y luego **Guardar resultado**.',
						'Un resultado editado se marca como **Editado por el organizador** para que todos vean que lo cambió el organizador. La edición mueve también el tiempo oficial del corredor.',
						'**Descargar resultados CSV** exporta los paneles.',
					],
				},
			],
		},
	],
};
