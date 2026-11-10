import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'run-a-self-timed-race',
	title: 'Correr una carrera con cronometraje propio',
	summary: 'Únete a una carrera abierta durante una ventana de tiempo, marca tu carrera como tu intento y corre de la línea de salida a la línea de meta cuando mejor te venga.',
	sections: [
		{
			heading: 'Qué es una carrera con cronometraje propio',
			blocks: [
				{
					type: 'p',
					text: 'Una carrera con cronometraje propio no tiene salida en grupo. El organizador abre una ventana, que puede durar hasta una semana, y corres el recorrido cuando quieras mientras esté abierta. Tu tiempo cuenta desde que cruzas la línea de salida hasta que cruzas la línea de meta, así que no hay tiempo de pistola.',
				},
				{
					type: 'p',
					text: 'Grabas tu intento con la app del móvil o con un reloj Wear OS. La web sirve para unirte y para ver los resultados; un navegador no puede grabar una carrera.',
				},
			],
		},
		{
			heading: 'Antes de salir',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre el evento de la carrera, en la web o en la app del móvil.',
						'Si hay más de un recorrido, elige primero el tuyo.',
						'Elige **Unirme e intentarlo**. Si ya has dicho **Me apunto**, ya estás dentro.',
						'Abre la app una vez mientras tengas señal, antes de salir. Así conoce la carrera, y el aviso de carrera y tu intento siguen funcionando donde no haya señal.',
					],
				},
			],
		},
		{
			heading: 'Empezar tu intento',
			blocks: [
				{
					type: 'steps',
					items: [
						'En la pestaña Correr de la app del móvil, el aviso de carrera muestra **Cronometraje propio** y cuándo se cierra la ventana.',
						'Toca **Esta carrera es mi intento**. Cambia a **Intento listo: toca Iniciar**; vuelve a tocarlo si cambias de idea.',
						'Pulsa Iniciar antes de llegar a la línea de salida y luego cruza la línea de salida en el sentido del recorrido.',
					],
				},
				{
					type: 'p',
					text: 'En un reloj Wear OS, la pantalla previa a la salida muestra CRONO PROPIO. Toca **Esta carrera es mi intento** y luego Empezar.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Una carrera que no marques como tu intento nunca se une a la competición: no envía posición en directo ni obtiene resultado. Así, una carrera con la que no pretendías competir nunca acaba en la clasificación.',
				},
			],
		},
		{
			heading: 'Los intentos y tu resultado',
			blocks: [
				{
					type: 'list',
					items: [
						'Puedes hacer más de un intento mientras la ventana esté abierta. Toca **Esta carrera es mi intento** antes de cada uno.',
						'Cuenta tu mejor llegada cronometrada por las dos líneas. Un intento más lento no la sustituye.',
						'Puede que tu resultado tenga que esperar a que el organizador lo apruebe. Hasta entonces se muestra como pendiente y no tiene puesto.',
						'Un resultado sin cruce de la línea de salida, como uno enviado desde un Apple Watch o desde una versión antigua de la app, se conserva, pero el organizador lo revisa antes de que cuente.',
					],
				},
				{
					type: 'p',
					text: 'Qué significan los tiempos de la clasificación se explica en [[guide:race-results-explained|Los resultados de carrera, explicados]].',
				},
			],
		},
	],
	sources: {
		title: '980e3fe539fa87ed',
		summary: '8200cb3990ca1c84',
		's0.heading': 'da16fddd6466ff82',
		's0.b0': 'b166c8e10ca64251',
		's0.b1': '9eb15ab29b32b50a',
		's1.heading': 'c682ac1a8b55d5bd',
		's1.b0.i0': 'f2699d62a364214c',
		's1.b0.i1': '15f502c0495a6810',
		's1.b0.i2': 'd67ce3877679d3b7',
		's1.b0.i3': 'd5058d744cf24c6b',
		's2.heading': '6e3e520b08e75a87',
		's2.b0.i0': '6b5b44bd7545a139',
		's2.b0.i1': '48bf3f903a530a73',
		's2.b0.i2': 'ff90c543a96100a6',
		's2.b1': '34ded6bec1fb4447',
		's2.b2': 'e9496d6a3325b124',
		's3.heading': '4ad1d4e8c17417b8',
		's3.b0.i0': 'a0858a05aad2d12a',
		's3.b0.i1': '82cda99fabf47908',
		's3.b0.i2': 'a6113125dae261a1',
		's3.b0.i3': '8e98409f10047bd7',
		's3.b1': '71fadd9d562da318',
	},
};
