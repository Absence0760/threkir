import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'park-courses',
	title: "Recorridos de parques: puntos de control, temporadas, meses y clasificaciones",
	summary: "Cómo un recorrido de parque cronometra tu carrera, por qué cuenta cada punto de control, cuándo empiezan una temporada y un mes y cómo ordenan a los corredores Más rápidos y Más completados.",
	sections: [
		{
			heading: "Qué es un recorrido de parque",
			blocks: [
				{ type: 'p', text: "Un recorrido de parque es un recorrido contrarreloj fijo por un sendero de un parque estatal o nacional. No hay organizador ni fecha de competición: córrelo cuando el parque esté abierto, y cualquier carrera que cubra todo el recorrido se cronometra en él. Los encontrarás en **Corre cuando quieras**, dentro de [[route:/races|Pruebas y recorridos]], con los más cercanos primero cuando indicas un lugar, o todos en [[route:/parks|Recorridos de parques]]. Elige **Recorridos** arriba en Pruebas y recorridos para ver todos los recorridos solos, sin el calendario de pruebas." },
				{
					type: 'list',
					items: [
						"Es una contrarreloj, no una prueba organizada. El sendero sigue abierto para todos y nadie lo controla, así que respeta las normas del parque y cede el paso a los demás en el sendero.",
						"Cada página de recorrido muestra la distancia, el desnivel positivo, la forma, la superficie y la dificultad, de dónde viene la línea del recorrido y si está abierto.",
						"Selecciona **Navegar este recorrido** para seguir el recorrido como una ruta. No se ofrece mientras el recorrido está cerrado.",
						"La **Guía del recorrido** de la página del recorrido indica dónde aparcar y cada giro en orden, con el nombre del sendero, además de los puentes, vados, cambios de superficie y subidas. Está redactada con datos del mapa; hasta que alguien la recorra en el parque, lo indica encima de la lista. La misma guía va en el archivo GPX del recorrido.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Un recorrido cerrado no admite tiempos nuevos: una carrera por él mientras está cerrado no se cronometra, y los tiempos que ya tiene siguen en sus clasificaciones. No lo corras hasta que vuelva a abrir. La página muestra cuándo se comprobó su estado por última vez." },
			],
		},
		{
			heading: "Puntos de control: por qué los atajos nunca cuentan",
			blocks: [
				{ type: 'p', text: "Además de la salida y la meta, un recorrido puede tener puntos de control por el camino. Tu carrera solo se cronometra si pasa por todos los puntos de control, en orden, entre la salida y la meta. Una carrera que corta una curva, se salta una zeta o atraviesa por el medio pierde un punto de control y no consigue tiempo." },
				{ type: 'p', text: "No te salgas del sendero marcado. Atajar daña el sendero, y los parques lo consideran una infracción de sus normas." },
			],
		},
		{
			heading: "Las temporadas siguen el reloj del parque",
			blocks: [
				{ type: 'p', text: "Una temporada es un año natural en la zona horaria del parque, no en la tuya. Las clasificaciones empiezan de nuevo a medianoche del 1 de enero donde está el parque." },
				{ type: 'p', text: "Por ejemplo, una carrera que empieza a las 22:00 del 31 de diciembre en un parque de Virginia cuenta para ese año, aunque tu teléfono esté en una zona horaria donde ya es 1 de enero." },
			],
		},
		{
			heading: "La clasificación Más rápidos",
			blocks: [
				{
					type: 'list',
					items: [
						"**Más rápidos** ordena a cada corredor por su mejor tiempo en el recorrido. Apareces una sola vez, con tu mejor carrera.",
						"Por defecto muestra este año. Selecciona **Este mes** para ver lo que va de mes, o **Histórico** para ver los mejores tiempos de siempre.",
						"Filtra por género o por grupo de edad. El filtro de edad solo incluye a quienes han aceptado compartir datos de salud, así que puede ser más corto que la clasificación completa.",
					],
				},
			],
		},
		{
			heading: "La clasificación Más completados",
			blocks: [
				{ type: 'p', text: "**Más completados** premia a los habituales. Cuenta los días en que completaste el recorrido, en la zona horaria del parque, así que varias vueltas el mismo día cuentan como una." },
			],
		},
		{
			heading: "Meses: una clasificación nueva cada mes",
			blocks: [
				{ type: 'p', text: "Las dos clasificaciones también van mes a mes. Un mes es un mes natural en la zona horaria del parque, desde la medianoche del día 1 hasta la medianoche del día 1 del mes siguiente, así que una carrera a las 23:30 del 31 de octubre en la hora del parque cuenta para octubre." },
				{
					type: 'list',
					items: [
						"Selecciona **Este mes** para ver lo que va de mes, y usa las flechas junto al nombre del mes para volver a meses anteriores.",
						"Cada recorrido en la página de un parque muestra cuántas personas lo han corrido este mes.",
						"Un tiempo en un recorrido de parque, en la página de tu carrera, muestra su puesto ese mes y ese año, por ejemplo N.º 2 en noviembre, n.º 9 en 2026. La pegatina **Recorrido de parque** de una imagen compartida muestra el puesto del mes, y también el del año cuando está entre los 10 primeros.",
						"Cuando termina un mes en la hora del parque, recibes en tu bandeja de entrada un aviso con tu mejor tiempo de ese mes en cada recorrido que corriste. Desactívalo con **Meses en recorridos de parque**: en la web, en [[route:/settings/notifications|Notificaciones]]; en la app del móvil, en **Notificaciones**, dentro de la pestaña **Tú**.",
						"Las insignias de meses de parque cuentan los meses en los que completaste un recorrido de parque, a los 3, 6, 12 y 24 meses. Cuentan recorridos completados, nunca puestos.",
					],
				},
			],
		},
		{
			heading: "Quién aparece en las clasificaciones",
			blocks: [
				{
					type: 'list',
					items: [
						"Necesitas iniciar sesión para ver las clasificaciones. Sin sesión, la página del recorrido sigue mostrando el recorrido y un enlace **Iniciar sesión**.",
						"El tiempo de una carrera que los demás no pueden ver no se les muestra.",
						"No verás a las personas que has bloqueado, y ellas no te verán a ti.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Una carrera se compara con los recorridos de parque en nuestros servidores poco después de guardarla o importarla, desde cualquier dispositivo. Un tiempo nuevo puede tardar unos minutos en aparecer en una clasificación." },
			],
		},
	],
	sources: {
		title: "80ff9e4c22672c3e",
		summary: "a8d0d3cdf47ef5c6",
		"s0.heading": "216fc084817bfda9",
		"s0.b0": "c202f382c7f5c297",
		"s0.b1.i0": "a8567bc2512800d1",
		"s0.b1.i1": "420575263613791d",
		"s0.b1.i2": "d69fbf280d3b46a0",
		"s0.b1.i3": "a75477f7d5a5a5bc",
		"s0.b2": "a9aa6fec9968fc90",
		"s1.heading": "0026d1ddae689c8a",
		"s1.b0": "f00cd3cca5bfc92f",
		"s1.b1": "36e6dc7fd586b7d7",
		"s2.heading": "5ba4de4e9cb351a4",
		"s2.b0": "f5cb979a283038fa",
		"s2.b1": "6afb246fc0e80841",
		"s3.heading": "f90c634a3c69c00f",
		"s3.b0.i0": "8bab47facf52e4fd",
		"s3.b0.i1": "01322b98d3fa4762",
		"s3.b0.i2": "a26ad1f8b547015d",
		"s4.heading": "d62c88ea85d104ce",
		"s4.b0": "23512913978ca5c1",
		"s5.heading": "2158104d68549d3e",
		"s5.b0": "f8cebd1b6b6f6d5c",
		"s5.b1.i0": "95832d49c27d961e",
		"s5.b1.i1": "e5fd55e453a25d9a",
		"s5.b1.i2": "0220ee50a2c3ffc2",
		"s5.b1.i3": "3c988cac91d6d886",
		"s5.b1.i4": "9f0fedf00dcae221",
		"s6.heading": "b119ed9eec93efe3",
		"s6.b0.i0": "bee88a50dcbbbfa2",
		"s6.b0.i1": "25229437ce8179b8",
		"s6.b0.i2": "c95241619d2e3582",
		"s6.b1": "f0b47eeb5f542fe4",
	},
};
