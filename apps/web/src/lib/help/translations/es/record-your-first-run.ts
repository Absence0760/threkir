import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'record-your-first-run',
	title: 'Grabar tu primera carrera',
	summary: 'Empieza una carrera en tu móvil, páusala y detenla con seguridad, consigue una buena señal GPS y descubre qué se guarda después.',
	sections: [
		{
			heading: 'Empezar a grabar',
			blocks: [
				{
					type: 'p',
					text: 'Las carreras se graban en la app del móvil o en un reloj. La app web muestra tus carreras, pero no puede grabar ninguna.',
				},
				{
					type: 'steps',
					items: [
						'Toca el botón grande en el centro de la barra inferior. Dice **Correr**, o **Registrar** si has activado gimnasio o nutrición; en ese caso, elige **Registrar carrera**.',
						'Toca **INICIAR**. La primera vez, tu móvil pide acceso a la ubicación: permítelo, o la carrera solo grabará el tiempo, sin distancia ni mapa.',
						'Mientras el GPS se prepara, corre una cuenta atrás de tres segundos, y luego arranca el reloj.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'En Android, elige **Permitir todo el tiempo** para la ubicación. Si solo das acceso mientras la app está abierta, puede que no se cuente la distancia que recorres con la pantalla apagada, aunque el reloj sigue corriendo. Consulta [[guide:location-permission|qué opción de ubicación elegir]].',
				},
				{
					type: 'illustration',
					id: 'record-your-first-run',
					alt: 'Un móvil con un gran botón redondo de inicio, que recibe la señal GPS de un satélite en el cielo.',
				},
			],
		},
		{
			heading: 'Pausar y detener',
			blocks: [
				{
					type: 'p',
					text: 'No hay pausa automática: el reloj corre hasta que lo pausas. Usa el botón de pausa para una parada que quieras dejar fuera de tu tiempo, y el botón de reanudar para seguir.',
				},
				{
					type: 'p',
					text: 'No pasa nada por esperar en un paso de peatones sin pausar. Después de la carrera, el tiempo **En movimiento** deja fuera los tramos en los que estuviste parado, y tu ritmo se calcula a partir del tiempo en movimiento.',
				},
				{
					type: 'steps',
					items: [
						'Para terminar, mantén pulsado el botón de detener. La indicación dice **Mantén para detener**, para que un toque accidental en el bolsillo no termine la carrera.',
						'El resumen **Carrera completada** muestra tu distancia, el **Tiempo**, el tiempo **En movimiento**, el ritmo y cualquier otro dato que haya medido tu móvil.',
						'Toca **Listo** para volver a la pantalla de inicio.',
					],
				},
			],
		},
		{
			heading: 'Cómo conseguir una buena señal GPS',
			blocks: [
				{
					type: 'list',
					items: [
						'Empieza al aire libre, lejos de edificios altos y de arboledas densas, para que durante la cuenta atrás haya una vista despejada del cielo.',
						'Si ves **Señal GPS perdida — sal a cielo abierto**, sigue adelante: el reloj sigue corriendo y la distancia vuelve a contar cuando regresa la señal.',
						'**GPS débil — distancia en pausa** significa que tu posición es demasiado incierta para contarla. La distancia se reanuda en cuanto mejora la señal.',
						'Mantén activados los servicios de ubicación y desactivado el ahorro de batería para la app, para que tu móvil no detenga la grabación en segundo plano.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Si la app se cierra a mitad de carrera, vuelve a abrirla: se te preguntará **¿Reanudar tu carrera?** y podrás reanudarla, terminarla ya o descartarla.',
				},
			],
		},
		{
			heading: 'Qué se guarda',
			blocks: [
				{
					type: 'p',
					text: 'Cuando te detienes, la carrera se guarda primero en tu móvil y luego se sube a tu cuenta. El resumen muestra **Sincronizada** cuando ya está a salvo en la nube, o **Guardada sin conexión.** si no has iniciado sesión. Una carrera que no se pudo subir se queda en el móvil y se reintenta más tarde.',
				},
				{
					type: 'list',
					items: [
						'Distancia, tiempo total, tiempo en movimiento y ritmo.',
						'Tu recorrido GPS, que dibuja el mapa y los parciales.',
						'El desnivel, los pasos y la frecuencia cardíaca si emparejaste una banda de frecuencia cardíaca.',
					],
				},
				{
					type: 'p',
					text: 'Quién puede ver la carrera depende de tu ajuste **Privacidad predeterminada de las carreras**, que puedes cambiar después para cualquier carrera concreta. Para ocultar dónde vives, configura las [[guide:privacy-zones|zonas de privacidad]] antes de compartir nada.',
				},
			],
		},
	],
	sources: {
		title: '70047f50b01f1af6',
		summary: 'dc170443668c395f',
		's0.heading': '30756af0134e4bf1',
		's0.b0': '6dc07a2b5e601838',
		's0.b1.i0': 'a7632a8cd2567c2c',
		's0.b1.i1': '68b860679cd99712',
		's0.b1.i2': 'a406181fe0c90b54',
		's0.b2': 'f776b4b4202d8779',
		's1.heading': '7c0f775fc550ae67',
		's1.b0': '7cdb0afab0e6c855',
		's1.b1': '1514c09a3d983d9e',
		's1.b2.i0': '2c86f71499d052af',
		's1.b2.i1': 'a2b9c26b2835d1ac',
		's1.b2.i2': 'c28a30ef42432d2f',
		's2.heading': 'cb9aedf1a5764367',
		's2.b0.i0': '35ba6295ed45225d',
		's2.b0.i1': '44f804dddcf3049e',
		's2.b0.i2': 'b8c55726529e022b',
		's2.b0.i3': '514cfcccb3fc6f5e',
		's2.b1': '2f0d094e06e813c3',
		's3.heading': 'f075ba7c6636fa8a',
		's3.b0': 'ef5a53403410399c',
		's3.b1.i0': 'ec005f0ead60e9e0',
		's3.b1.i1': 'e0fd699761f32367',
		's3.b1.i2': '1d33b3ee8d0be1b8',
		's3.b2': 'a8054fd15c256c3c',
		's0.b3': '21307fc19189cc42',
	},
};
