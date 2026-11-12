import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'adjust-a-plan-with-ai',
	title: 'Ajustar un plan de entrenamiento con IA',
	summary: 'Describe con tus palabras un cambio en tu plan, revisa cada modificación sugerida y guarda solo cuando estés de acuerdo.',
	sections: [
		{
			heading: 'Qué puede cambiar',
			blocks: [
				{
					type: 'p',
					text: 'Ajustar con IA convierte una petición como *pasa mi tirada larga al sábado* o *haz más suave la semana que viene* en cambios en un plan que tienes guardado. Puede mover un entrenamiento a otro día de la misma semana, intercambiar dos días, subir o bajar un poco una semana, convertir una semana en semana de recuperación o saltar un entrenamiento.',
				},
				{
					type: 'p',
					text: 'Cada cambio lo aplican las reglas de planes de Threkir. La IA nunca escribe un entrenamiento, una distancia ni un ritmo, así que una petición como *añade una sesión de cuestas* recibe una nota de que no puede hacerlo. Para todo lo demás, usa **Editar plan**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ajustar con IA solo está en la web, y puede que aún no esté activado. Si **Ajustar con IA** no aparece en **Ajustar plan**, no está disponible para ti.',
				},
			],
		},
		{
			heading: 'Pedir un cambio',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre tu plan en la web y selecciona **Ajustar plan**.',
						'Elige **Ajustar con IA**.',
						'Escribe qué quieres cambiar y selecciona **Sugerir cambios**.',
						'Lee los **Cambios sugeridos**: cada entrenamiento que se mueve, se salta o se suaviza, y cada objetivo semanal que cambia, antes y después.',
						'Selecciona **Aplicar cambios sugeridos por la IA** para guardarlos. Hasta entonces, tu plan no ha cambiado; selecciona **Cancelar** para dejarlo como estaba.',
					],
				},
			],
		},
		{
			heading: 'Comprobaciones de seguridad antes de guardar',
			blocks: [
				{
					type: 'list',
					items: [
						'Los cambios que llevarían una semana a la zona de alto riesgo de lesión según tu entrenamiento reciente no se pueden aplicar. La página indica qué semana.',
						'Si los cambios hacen una semana más dura de lo que tu entrenamiento reciente permite, o ponen dos sesiones duras en días seguidos, se te pregunta **¿Aplicar cambios más duros?** y tienes que elegir **Aplicar igualmente**.',
						'Una sugerencia que no se podía aplicar con seguridad se descarta, y la página te lo indica.',
					],
				},
			],
		},
		{
			heading: 'Qué utiliza',
			blocks: [
				{
					type: 'list',
					items: [
						'Cada petición gasta uno de tus mensajes diarios del Entrenador IA, el mismo cupo que el del Entrenador.',
						'Necesita el aviso de IA más reciente. Si se te pide aceptarlo, selecciona **Revísala en Ajustes** y acéptalo allí.',
						'A la IA solo se envían los próximos entrenamientos de tu plan y el cambio que has escrito.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'También puedes pedirle al Entrenador que cambie tu plan. Responde con un enlace que abre Ajustar con IA con tu petición ya escrita.',
				},
			],
		},
	],
	sources: {
		title: '3430390db6cef427',
		summary: '0b8f143261af9bcc',
		's0.heading': '44fa39d8b77c49be',
		's0.b0': '38fcc465ef1aec71',
		's0.b1': '7e6eec922334abd2',
		's0.b2': 'ca366aa955882170',
		's1.heading': 'f445fc4ffc97bebf',
		's1.b0.i0': '62be50b834eee366',
		's1.b0.i1': '490a29939b6ffad0',
		's1.b0.i2': '8dd005960648769c',
		's1.b0.i3': '6b71202d85d1ca61',
		's1.b0.i4': '1372a2a63c642a43',
		's2.heading': 'd9ef6a00bed5abfb',
		's2.b0.i0': '5b077f2018bffd38',
		's2.b0.i1': '2aae15cab49e816a',
		's2.b0.i2': 'aa84c731a647d1f3',
		's3.heading': '7e05806066a320c6',
		's3.b0.i0': '62c07e209d9ce339',
		's3.b0.i1': '1418c266b519f9d9',
		's3.b0.i2': '5de71e71f15f24a2',
		's3.b1': '12d00dbd647acb4c',
	},
};
