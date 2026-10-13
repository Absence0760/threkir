import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'using-help',
	source: 'a9e53ac06c08edd3',
	title: 'Encontrar ayuda en la app',
	summary: 'Dónde están las guías de ayuda, cómo buscar en ellas y cómo saltar desde una pantalla a la guía que la explica.',
	sections: [
		{
			heading: 'Abrir la ayuda',
			blocks: [
				{
					type: 'steps',
					items: [
						'Selecciona tu nombre en la parte inferior de la barra lateral. En una ventana estrecha la barra lateral se reduce a iconos, así que selecciona en su lugar el avatar redondo con tu inicial.',
						'Elige **Ayuda** en el menú que se abre.',
					],
				},
				{
					type: 'p',
					text: 'La página de contenidos muestra todas las guías por tema. Los chips de **Mostrar guías para** reducen la lista a las guías escritas para ti, como **Organizadores** o **Espectadores**; **Todas** vuelve a mostrarlo todo.',
				},
			],
		},
		{
			heading: 'Buscar en las guías',
			blocks: [
				{
					type: 'p',
					text: 'Escribe una o dos palabras en **Buscar en las guías**, en la parte superior de [[route:/help|Ayuda]], y pulsa **Buscar**. Primero salen las guías con tus palabras en el título, luego las que las mencionan en el resumen y después el resto.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Las mayúsculas y los acentos no importan, así que *cafe* encuentra *Café*. Cada palabra que escribas tiene que aparecer en alguna parte de una guía para que esta aparezca en la lista.',
				},
			],
		},
		{
			heading: 'Ayuda desde la pantalla en la que estás',
			blocks: [
				{
					type: 'p',
					text: 'Una pantalla que tiene guía muestra un enlace **Cómo funciona** cerca de su título. Abre la guía de esa pantalla; si la tratan varias guías, abre una lista breve para elegir.',
				},
				{
					type: 'p',
					text: 'Algunas tarjetas y ajustes llevan un pequeño botón redondo *i*. Explica la función en una o dos frases y, cuando una guía da más detalles, termina con **Leer la guía**.',
				},
			],
		},
		{
			heading: 'Leer una guía',
			blocks: [
				{
					type: 'list',
					items: [
						'Las insignias bajo el título indican a qué apps se aplica la guía y si necesitas algo antes, como Pro o un rol de administrador del club.',
						'**En esta página** enumera las secciones de una guía larga y salta a la que elijas.',
						'**Guías relacionadas**, al final, te indica lo que probablemente necesites después.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Las guías se muestran en el idioma en que está configurada la app. Una guía que aún no se ha traducido a ese idioma se muestra en inglés, con una nota arriba que lo indica.',
				},
			],
		},
	],
};
