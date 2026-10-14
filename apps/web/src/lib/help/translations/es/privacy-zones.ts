import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'privacy-zones',
	title: 'Ocultar tu casa con zonas de privacidad',
	summary: 'Dibuja un círculo alrededor de tu casa, tu trabajo o cualquier otro lugar para que el inicio y el final de tus carreras y rutas dentro de él queden ocultos para todos menos para ti.',
	sections: [
		{
			heading: 'Qué hace una zona de privacidad',
			blocks: [
				{
					type: 'p',
					text: 'Una zona de privacidad es un círculo en el mapa. Cuando una carrera o una ruta empieza o termina dentro de una, esa parte del recorrido se recorta antes de que nadie más la vea, de modo que la línea parece empezar y terminar en el borde del círculo.',
				},
				{
					type: 'list',
					items: [
						'Se aplica a lo que ven los demás: carreras y rutas compartidas, tu perfil público, el feed, los mapas de calor y la página de seguimiento en directo.',
						'Se aplica tanto a las carreras que ya has grabado como a las nuevas, porque el recorrido se recorta cada vez que otra persona lo ve.',
						'Tú siempre ves tu recorrido completo, y los archivos que exportas para ti también lo conservan completo.',
					],
				},
				{
					type: 'illustration',
					id: 'privacy-zones',
					alt: 'Una ruta empieza en una casa dentro de un círculo. La parte dentro del círculo queda oculta para los demás, así que la línea que ven empieza en el borde del círculo.',
				},
			],
		},
		{
			heading: 'Añadir una zona en la web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre [[route:/settings/privacy|Privacidad y uso compartido]] en Configuración.',
						'En **Zonas de privacidad**, selecciona **Añadir una zona**.',
						'Haz clic en el mapa donde quieras centrar la zona, o selecciona **Usar ubicación actual**, y luego arrastra el marcador para ajustarla.',
						'Fija el **Radio**. Todo lo que quede dentro del círculo rojo se oculta en lo que compartes públicamente.',
						'Selecciona **Añadir zona**. La zona se guarda al instante.',
					],
				},
				{
					type: 'p',
					text: 'Para borrar una zona, selecciona **Eliminar** junto a ella y confirma. Al eliminar una zona, esa área vuelve a mostrarse en lo que compartes públicamente.',
				},
			],
		},
		{
			heading: 'Añadir una zona en la app del móvil',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre la pestaña **Tú**, luego **Preferencias**, y en **Privacidad y uso compartido** toca **Zonas de privacidad**.',
						'Toca el mapa para colocar una zona. Usa **Buscar lugares…** o **Ubicarme** para mover antes el mapa.',
						'Ajusta el control deslizante de **Radio**.',
						'Toca **Guardar**. No cambia nada hasta que guardes.',
					],
				},
				{
					type: 'p',
					text: 'Para borrar una zona, toca su marcador y confirma, o usa **Borrar todo** para quitar todas las zonas a la vez. Después toca **Guardar**; al eliminar una zona, esa área vuelve a mostrarse en lo que compartes públicamente.',
				},
			],
		},
		{
			heading: 'Cómo elegir una buena zona',
			blocks: [
				{
					type: 'list',
					items: [
						'Centra la zona cerca de tu puerta, pero no justo encima, para que el borde del círculo no apunte directamente a tu casa.',
						'Hazla lo bastante grande para cubrir unas cuantas calles. Un círculo diminuto aún puede delatar dónde vives.',
						'Añade una para cualquier lugar desde el que salgas a menudo, como el trabajo o la casa de un amigo.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Las zonas solo recortan la línea del mapa. El título, la descripción y las fotos de una carrera se muestran tal como los escribiste, así que no pongas direcciones en ellos.',
				},
			],
		},
	],
	sources: {
		title: 'd9e7d40ed8ec1d93',
		summary: '04c4913e2da59def',
		's0.heading': '27ee9eff5654fc40',
		's0.b0': '0786f273bb90019e',
		's0.b1.i0': 'ae791e6bb37bf75e',
		's0.b1.i1': 'f895445f10db7b57',
		's0.b1.i2': '591dec4de03df2a3',
		's1.heading': 'cc3973572fe81b73',
		's1.b0.i0': 'a9f7c5a79d8779f0',
		's1.b0.i1': 'de234d8646b8454f',
		's1.b0.i2': '35c82b7aef764872',
		's1.b0.i3': '1d8fc63d18b8641a',
		's1.b0.i4': '150b03da903ccf27',
		's1.b1': 'b395019ec1836f1e',
		's2.heading': 'd50fe7d487cde78b',
		's2.b0.i0': '0f37a464ec66cdc7',
		's2.b0.i1': 'e3478863d167e8fe',
		's2.b0.i2': 'ca9cc061ff309425',
		's2.b0.i3': '2f1655078cb4ae12',
		's2.b1': 'cb30c404ac96aa57',
		's3.heading': 'ea3ab9efa7240662',
		's3.b0.i0': '9184e7f4329c71d3',
		's3.b0.i1': '7e6aff2443fca79b',
		's3.b0.i2': '2d441105a1624ed1',
		's3.b1': '20c32d436fe0799c',
		's0.b2': '9bfc49abe8494ae1',
	},
};
