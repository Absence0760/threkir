import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'build-a-gym-routine',
	title: 'Crear una rutina de gimnasio',
	summary: 'Convierte un entrenamiento que impartes o repites en una rutina reutilizable con series, repeticiones, carga, descanso y superseries, y síguela de forma guiada o compártela con tu club.',
	sections: [
		{
			heading: 'Dos formas de empezar',
			blocks: [
				{
					type: 'list',
					items: [
						'Desde cero: abre [[route:/gym/routines|Rutinas]] y pulsa **Nueva rutina**. En la web también puedes ir a [[route:/plans/new|Nuevo plan]] y elegir **Rutina de gimnasio**.',
						'A partir de un entrenamiento que ya registraste: ábrelo en tu registro de gimnasio y pulsa **Guardar como rutina**. Sus ejercicios y series pasan a ser los objetivos de la rutina. **Repetir el último**, en cambio, empieza un registro nuevo a partir del mismo entrenamiento.',
					],
				},
				{
					type: 'p',
					text: 'En la app móvil, abre la pantalla de gimnasio y toca **Rutinas** y luego **Nueva rutina**.',
				},
			],
		},
		{
			heading: 'Rellenarla',
			blocks: [
				{
					type: 'steps',
					items: [
						'Dale un **Nombre de la rutina** que haga referencia al día y no al primer ejercicio, por ejemplo «Bootcamp A».',
						'Escribe el nombre del primer ejercicio. Reutiliza un nombre que ya registres, para que tus récords de ese ejercicio estén en un solo sitio.',
						'En **Medido por**, elige cómo se mide: peso y repeticiones, peso corporal, tiempo o distancia. Las filas de series cambian para pedir el objetivo correspondiente.',
						'Para cada serie, indica un **Tipo de serie** y sus objetivos, como **Repeticiones objetivo** y peso, y un **Descanso (s)**. Pulsa **Añadir serie** para añadir más series.',
						'Para hacer dos ejercicios seguidos, activa **Superserie con el siguiente ejercicio** en el primero.',
						'Pulsa **Añadir ejercicio** para el siguiente y repite.',
						'Si quieres, abre **Avanzado** y elige una regla de **Progresión**, que sugiere las cifras de la próxima sesión a partir del resultado de esta. Si la dejas en Ninguna, tus objetivos se quedan tal como los escribiste.',
						'Añade las **Notas (opcional)** que quieras y pulsa **Guardar rutina**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Cada fila de serie es un objetivo, no un registro. Es lo que rellena una sesión iniciada desde la rutina, y aun así puedes cambiar las cifras sobre la marcha.',
				},
			],
		},
		{
			heading: 'Hacerla',
			blocks: [
				{
					type: 'p',
					text: 'Abre la rutina y pulsa **Iniciar rutina** (en la app móvil, **Iniciar sesión**). Se te guía serie a serie con tu objetivo a la vista: registra lo que hiciste y pulsa **Completar serie**, o **Saltar serie**, con un temporizador de descanso entre series. Pulsa **Finalizar** al terminar y la sesión se guarda en tu registro de gimnasio, junto con la comparación con lo planificado.',
				},
			],
		},
		{
			heading: 'Compartirla con una clase',
			blocks: [
				{
					type: 'list',
					items: [
						'**Publicar en un club**: elige el club en **Elige un club…** y pulsa **Publicar**. Aparece en la pestaña **Plantillas** de ese club, en **Plantillas de rutina de gimnasio**, donde los miembros pulsan **Adoptar** para obtener su propia copia. Los cambios en una copia no modifican tu original.',
						'**Publicar en la biblioteca pública**: cualquier persona con la sesión iniciada puede verla y adoptarla. Tus entrenamientos registrados siguen siendo privados.',
					],
				},
				{
					type: 'p',
					text: '¿Vas a impartir una clase de pago basada en la rutina? Consulta [[guide:host-a-paid-gym-class|Organizar una clase de pago de HIIT, fuerza o bootcamp]].',
				},
			],
		},
	],
	sources: {
		title: 'e154719ab6c6db3a',
		summary: 'c15dfd024f683826',
		's0.heading': 'a52411b1c11cf590',
		's0.b0.i0': '83c54adc1d0ea60f',
		's0.b0.i1': 'eecbf0bc154dab9e',
		's0.b1': '8f85ecd63a29a0a3',
		's1.heading': 'd222e97495049181',
		's1.b0.i0': '81da95efe111f60e',
		's1.b0.i1': '2d229299f8d76acb',
		's1.b0.i2': '82dd1ff342d922c0',
		's1.b0.i3': '5361d720e294f93d',
		's1.b0.i4': 'eadce6bf2e1f99a2',
		's1.b0.i5': '8e0bc50c1d08b6c7',
		's1.b0.i6': '47f7b227af1d250a',
		's1.b0.i7': '2a9bb2561495600e',
		's1.b1': '52bd55355e109053',
		's2.heading': '958ca26c6a61f02f',
		's2.b0': 'f393e332c6ec9a52',
		's3.heading': 'aab7baa90c561d6b',
		's3.b0.i0': 'd51e222a02a3c044',
		's3.b0.i1': 'fc99e8218cc68a71',
		's3.b1': '28cc92b70c319919',
	},
};
