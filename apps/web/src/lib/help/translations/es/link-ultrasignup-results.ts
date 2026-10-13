import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'link-ultrasignup-results',
	title: 'Vincular tus resultados de UltraSignup',
	summary: 'Busca tu perfil de UltraSignup por nombre, confirma cuál de esas personas eres tú e importa un resultado de ultra o trail desde el calendario de carreras.',
	sections: [
		{
			heading: 'Antes de empezar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'La importación de UltraSignup solo está en la web y permanece desactivada hasta que se habilite. Si la tarjeta de UltraSignup no aparece en Integraciones, o dice **La importación de UltraSignup aún no está disponible. parkrun y el pegado manual siguen funcionando.**, aún puedes añadir un resultado pegándolo en el calendario de carreras.',
				},
				{
					type: 'p',
					text: 'UltraSignup gestiona las inscripciones y los resultados de muchas carreras de trail y ultra. Si vinculas tu perfil una vez, no tendrás que volver a escribir tu nombre ni tu dorsal al importar un resultado.',
				},
			],
		},
		{
			heading: 'Vincular tu perfil',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre [[route:/settings/integrations|Integraciones]] en Configuración y busca la tarjeta de UltraSignup.',
						'En **Encuentra tu perfil de UltraSignup**, introduce tu **Nombre** y tu **Apellido** tal como los escribes al inscribirte en carreras y selecciona **Buscarme**.',
						'UltraSignup muestra a todas las personas con ese nombre. Usa la edad, el número de resultados y las carreras más recientes de cada una para reconocerte.',
						'En **¿Cuál de estas personas eres tú?**, selecciona **Soy yo** en tu entrada.',
					],
				},
				{
					type: 'p',
					text: 'La tarjeta muestra ahora **Vinculado como** con tu nombre y tu número de UltraSignup. Si elegiste a la persona equivocada, selecciona **Desvincular** y vuelve a buscar. Las carreras que ya importaste se conservan al desvincular.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si ves **UltraSignup no tiene a nadie con ese nombre. Revisa cómo lo escribes al inscribirte.**, prueba con la grafía exacta de tus inscripciones, incluido cualquier segundo nombre o guion.',
				},
			],
		},
		{
			heading: 'Importar un resultado desde el calendario de carreras',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre [[route:/races|Carreras]] y busca la carrera en la que corriste.',
						'Selecciona **Importar mi resultado**. El importador muestra con qué identidad está importando.',
						'Confirma la importación. Solo se trae tu propio resultado de esa carrera, emparejado por el id de carrera de UltraSignup y la fecha de la carrera.',
					],
				},
				{
					type: 'p',
					text: 'El resultado llega como una carrera con tu tiempo oficial y tus puestos. Si grabaste tú la carrera, abre esa carrera en su lugar: cuando coincide con una carrera del calendario, te pregunta si era esa carrera, y al seleccionar **Importar resultado** se añade el resultado oficial a la carrera que ya tienes en vez de crear una segunda.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Solo se importan resultados de carreras terminadas, y una carrera cuyo id o fecha no coincide se omite en lugar de adivinarse. Todavía hay muy pocas carreras de UltraSignup en el calendario, así que puede que la tuya no aparezca; en ese caso, usa **Pegar tu resultado** en el calendario de carreras.',
				},
				{
					type: 'p',
					text: 'Si ves **Primero vincula tu perfil de UltraSignup en Ajustes y luego importa desde aquí.**, vincula tu perfil como se explica arriba y vuelve.',
				},
			],
		},
	],
	sources: {
		title: '1c3d3ccace74b014',
		summary: 'f2fca5922e80c09a',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '0c7ce54419de8a75',
		's0.b1': '44ce80029649ec21',
		's1.heading': '9585e27668c04a9f',
		's1.b0.i0': '5c97b00e1a40a36b',
		's1.b0.i1': 'c74c3876783d3d3e',
		's1.b0.i2': 'a2c9f8d1aa769e71',
		's1.b0.i3': '583ce1f06db5e7a3',
		's1.b1': '75c4a2aecaf4f626',
		's1.b2': 'a780f42937b826b1',
		's2.heading': '2beec2f1afabca9b',
		's2.b0.i0': 'b25aba40145c665f',
		's2.b0.i1': 'bd2e53852db627ea',
		's2.b0.i2': '6dce444ee6e264da',
		's2.b1': 'e5693507bec3f21c',
		's2.b2': '041b5d6a68e26cfe',
		's2.b3': '01220bce8ab2d8b5',
	},
};
