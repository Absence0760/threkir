import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'log-a-meal-from-a-photo',
	title: 'Registrar una comida desde una foto',
	summary: 'Haz una foto de tu plato, deja que Threkir calcule qué hay en él, y revisa y edita cada elemento antes de que pase a tu registro de alimentos.',
	sections: [
		{
			heading: 'Antes de empezar',
			blocks: [
				{
					type: 'list',
					items: [
						'Registrar desde una foto forma parte de Pro. Registrar alimentos a mano sigue siendo gratis.',
						'Usa IA, así que necesita el aviso de IA más reciente. Si se te pide aceptarlo, abre el Entrenador y acéptalo allí.',
						'La foto solo se usa para calcular qué hay en el plato. Los datos de ubicación y de la cámara se eliminan antes de enviarla, y Threkir no guarda la foto.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Puede que aún no esté activado. Si no ves **Registrar desde una foto**, no está disponible para ti.',
				},
			],
		},
		{
			heading: 'En la web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre la página [[route:/nutrition/log|Registrar comida]].',
						'En **Registrar desde una foto**, selecciona **Elegir una foto** y escoge una imagen de tu comida.',
						'Añade una **Nota (opcional)** si ayuda, por ejemplo media ración.',
						'Selecciona **Estimar**.',
					],
				},
			],
		},
		{
			heading: 'En la app móvil',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre **Fitness**, elige la pestaña **Nutrición** y toca el botón de cámara, **Registrar desde una foto**.',
						'Toca **Hacer una foto** o **Elegir una foto**.',
						'Añade una **Nota (opcional)** si ayuda y toca **Estimar**.',
					],
				},
			],
		},
		{
			heading: 'Revisar antes de guardar',
			blocks: [
				{
					type: 'p',
					text: 'En **Revísalo antes de guardar** aparece cada alimento con sus calorías, proteínas, carbohidratos y grasas. Son estimaciones, así que revísalas.',
				},
				{
					type: 'list',
					items: [
						'Cambia cualquier nombre o cifra que parezca incorrecto. Los elementos marcados con **Estimación poco fiable** son los que más conviene revisar.',
						'Quita todo lo que no esté en tu plato.',
						'Elige la **Comida** a la que pertenece.',
						'Selecciona **Guardar entradas** para añadir lo que quede a tu registro de alimentos. Antes de eso no se guarda nada.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si no se reconoce ningún alimento, o has registrado muchas fotos en la última hora, añade la comida a mano como siempre.',
				},
			],
		},
	],
	sources: {
		title: 'bbdc9660a287e7c1',
		summary: 'aeef5fef4857acdc',
		's0.heading': '74e492d5d0df0bab',
		's0.b0.i0': 'd03e553125a96101',
		's0.b0.i1': 'd8c1c7bda37cffa1',
		's0.b0.i2': '63338ba4abc28ffc',
		's0.b1': '6791908473990cc8',
		's1.heading': '1e1b85a2667ca4d5',
		's1.b0.i0': '95844e8f3912970e',
		's1.b0.i1': '74bd9cd2cdc290a4',
		's1.b0.i2': 'e1f5d3b8c8fe13e4',
		's1.b0.i3': '945cfae0c52315dc',
		's2.heading': 'f21eaef94c685b5c',
		's2.b0.i0': 'c010f5524e29e935',
		's2.b0.i1': '788614966879c6fe',
		's2.b0.i2': 'c74ad67ce20e5723',
		's3.heading': 'a87450ed45241ef4',
		's3.b0': 'a770f2d0fc04e051',
		's3.b1.i0': 'ed3985f616eca37f',
		's3.b1.i1': '88c6d0416eae03ab',
		's3.b1.i2': 'ffc4a5ff20130b13',
		's3.b1.i3': '8f4ca5857c9f1f76',
		's3.b2': '8fea5a4dccf15c27',
	},
};
