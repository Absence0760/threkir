import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'link-ultrasignup-results',
	source: '0ad8552abbcc91f8',
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
};
