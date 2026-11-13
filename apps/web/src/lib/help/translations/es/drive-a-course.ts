import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'drive-a-course',
	title: "Conducir el recorrido de una prueba antes de que se celebre",
	summary: "Abre un recorrido público en tu app de mapas, mira qué tramos no puede seguir y deja que la app del móvil te lea en voz alta las notas del recorrido mientras conduces.",
	sections: [
		{
			heading: "Qué hace",
			blocks: [
				{ type: 'p', text: "En una ruta pública o una prueba con recorrido público, **Conducir el recorrido** divide el recorrido en tramos que Google Maps, Mapas de Apple o Waze pueden seguir. Tu app de mapas se encarga de guiarte, también en CarPlay y Android Auto." },
				{
					type: 'list',
					items: [
						"Google Maps admite varias paradas por tramo. Mapas de Apple y Waze admiten un solo destino cada vez, así que abres cada tramo por turnos.",
						"Los recorridos de las pruebas usan caminos, puentes y calles cortadas. La lista bajo los tramos muestra las partes que la app de mapas no puede seguir, para que sepas qué no verás.",
						"La ruta de la app de mapas es solo orientativa. Las notas siguen el recorrido real.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Esta función se está activando poco a poco. Si un recorrido público no muestra **Conducir el recorrido**, todavía no está disponible para ti." },
			],
		},
		{
			heading: "Abrir un recorrido en tu app de mapas",
			blocks: [
				{
					type: 'steps',
					items: [
						"Abre la ruta o la prueba y selecciona **Conducir el recorrido**.",
						"Elige tu app de mapas y selecciona **Ir a la salida**.",
						"En la salida, abre el tramo 1. Cuando termine un tramo, abre el siguiente.",
					],
				},
				{ type: 'p', text: "La página web también muestra cada nota del recorrido con su distancia, y puedes imprimir la lista para un acompañante." },
			],
		},
		{
			heading: "Escuchar las notas del recorrido en el móvil",
			blocks: [
				{
					type: 'steps',
					items: [
						"En la app del móvil, abre la ruta o la prueba y toca **Conducir el recorrido**.",
						"Lee el aviso de seguridad y toca **Entendido**. Solo aparece una vez en cada móvil.",
						"Toca **Iniciar notas habladas**, cambia a tu app de mapas y bloquea el móvil.",
					],
				},
				{ type: 'p', text: "Cada avituallamiento, corte, subida, peligro y nota se lee unos 15 segundos antes de llegar y otra vez al llegar. Si te unes a mitad, las notas empiezan donde estás. Se detienen en la meta o tras 10 minutos fuera del recorrido. Toca **Detener** para pararlas antes." },
				{ type: 'note', tone: 'caution', text: "Úsalo con un acompañante o con el móvil en un soporte, y no toques el móvil mientras conduces. Respeta las normas y señales de tráfico, y recuerda que las calles del recorrido pueden estar cortadas el día de la prueba." },
			],
		},
	],
	sources: {
		"title": "bbb89d013c30ae16",
		"summary": "48a420988cbd14e8",
		"s0.heading": "c74ea9dc9cd25b58",
		"s0.b0": "0c0cd5387f11ea68",
		"s0.b1.i0": "f99832ea6336c2e7",
		"s0.b1.i1": "f1890d3bd7eb5850",
		"s0.b1.i2": "2a2afee7d8920207",
		"s0.b2": "7d8297dee5795cc5",
		"s1.heading": "bcc63fa1329139a9",
		"s1.b0.i0": "14946890d3f8e349",
		"s1.b0.i1": "d191e63d2defd3a9",
		"s1.b0.i2": "886b24e27ccf472f",
		"s1.b1": "96f5e8e63b56c989",
		"s2.heading": "5d546a4fc1ae50a1",
		"s2.b0.i0": "c555d1adaded1b5f",
		"s2.b0.i1": "72929bf136e6a2eb",
		"s2.b0.i2": "888f501170932dde",
		"s2.b1": "d5bf7e3b65385652",
		"s2.b2": "86d1be053314ad10"
	},
};
