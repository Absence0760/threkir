import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'build-a-session-plan',
	title: 'Crear un plan de sesión de yoga, pilates o movilidad',
	summary: 'Escribe una secuencia cronometrada de posturas, flujos y repeticiones con movimientos por lado e indicaciones, y luego enseña con ella, asóciala a una clase y síguela.',
	sections: [
		{
			heading: 'Dónde crearlo',
			blocks: [
				{
					type: 'p',
					text: 'Los planes de sesión se escriben en la web. La app móvil los muestra y los reproduce, pero aún no tiene editor.',
				},
				{
					type: 'list',
					items: [
						'Para ti: abre [[route:/plans/new|Nuevo plan]] y elige **Plan de sesión**, o pulsa **Nueva sesión** en [[route:/sessions|Sesiones]].',
						'Para tu club: en la pestaña **Plantillas** del club, pulsa **Añadir plantilla** y elige **Plan de sesión**. Se guarda como plantilla del club al momento.',
					],
				},
			],
		},
		{
			heading: 'Rellenarlo',
			blocks: [
				{
					type: 'steps',
					items: [
						'Dale un **Título** que nombre la secuencia, como «Flujo de apertura de cadera, 45 min».',
						'Añade una **Disciplina** (por ejemplo, yoga vinyasa) y el **Equipo** que la gente debe tener preparado, como una esterilla o un reformer.',
						'Si quieres, pulsa **Añadir bloque** para dividirlo en secciones como Calentamiento, De pie y Enfriamiento. Un plan sin bloques se reproduce de principio a fin.',
						'Pulsa **Añadir movimiento** para cada postura o ejercicio y escribe su nombre en **Movimiento**.',
						'Elige su **Tipo**: **Mantener** para una postura cronometrada, **Flujo** para una secuencia de movimiento cronometrada o **Reps.** para un ejercicio por repeticiones. Luego introduce los **Segundos** o las **Repeticiones**, y el **Bloque** al que pertenece.',
						'Marca **Por lado (izquierda y derecha)** en todo lo que se haga a cada lado. Se reproduce una vez por lado, así que dura el doble.',
						'Si quieres, añade un **Tempo** y una **Indicación**, la pauta de respiración o alineación que se muestra junto al movimiento mientras alguien lo sigue.',
						'Comprueba la duración estimada que el editor calcula por ti y pulsa **Guardar**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Mientras escribes, se sugieren nombres de movimientos de tus planes anteriores. Elegir una sugerencia hace que la misma postura se escriba igual en todas partes.',
				},
			],
		},
		{
			heading: 'Asociarlo a una clase',
			blocks: [
				{
					type: 'list',
					items: [
						'Al crear una clase, elige el plan en **Plan de sesión**.',
						'¿Ya has creado la clase? En la página de la clase, los organizadores pulsan **Asociar a un evento de clase** en la tarjeta **Secuencia de la sesión**.',
					],
				},
				{
					type: 'p',
					text: 'Los asistentes ven entonces la secuencia completa en la página de la clase. Un plan privado sigue siendo privado para todos los demás, pero las personas de una clase a la que lo asocies pueden verlo.',
				},
			],
		},
		{
			heading: 'Seguirlo',
			blocks: [
				{
					type: 'p',
					text: 'Abre el plan y pulsa **Iniciar sesión**. Las posturas y los flujos cronometrados avanzan solos; en las repeticiones, pulsa **Hecho** al terminar. Puedes **Pausar**, **Reanudar**, **Saltar** un paso o **Abandonar**. Cuando terminas, se guarda en tu registro de gimnasio como entrenamiento.',
				},
				{
					type: 'p',
					text: 'La app móvil reproduce la misma sesión guiada, lee las indicaciones en voz alta, mantiene la pantalla encendida y sigue contando el tiempo si cambias a otra app.',
				},
			],
		},
		{
			heading: 'Compartirlo',
			blocks: [
				{
					type: 'list',
					items: [
						'**Hacer pública** permite que cualquiera lo encuentre y lo siga. **Copiar enlace para compartir** hace público el plan y copia un enlace que funciona sin iniciar sesión.',
						'**Publicar en un club**: elige el club en **Elige un club…** y pulsa **Publicar**. Aparece en **Plantillas de sesión**, en la pestaña **Plantillas** del club, y los miembros pulsan **Adoptar** para obtener su propia copia.',
					],
				},
			],
		},
	],
	sources: {
		title: '2761214d4528b755',
		summary: '6ed93f306126bfd5',
		's0.heading': '75ab7687d1fdc4e6',
		's0.b0': '4c2393e2453c0847',
		's0.b1.i0': 'be6a427f8e3575ab',
		's0.b1.i1': '43033b89a725981f',
		's1.heading': 'd222e97495049181',
		's1.b0.i0': 'e1da2dcf855fd8cd',
		's1.b0.i1': '117837344c17aa7d',
		's1.b0.i2': '2e19d15f6adb30c7',
		's1.b0.i3': '4178a74d986586c6',
		's1.b0.i4': 'ba82220d774c7f84',
		's1.b0.i5': '03673097f36c78e9',
		's1.b0.i6': 'd02405ef4e9be33a',
		's1.b0.i7': '4f883b9f98fe5258',
		's1.b1': '63d86fc0ace9cb60',
		's2.heading': '27bf4831df1b4047',
		's2.b0.i0': '08f6e2680c9d0de7',
		's2.b0.i1': '91f068b693756ac2',
		's2.b1': '9021887b2281f1ca',
		's3.heading': '273869c12606c741',
		's3.b0': 'bfc8888c6226cf77',
		's3.b1': '4c67ea01c09f80f8',
		's4.heading': '692991f8b622c079',
		's4.b0.i0': '548fec5550dfaa6b',
		's4.b0.i1': '21ced8342dc5228c',
	},
};
