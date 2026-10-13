import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'record-your-first-run',
	source: '9587d8580082759d',
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
					text: 'En Android, elige **Permitir todo el tiempo** para la ubicación. Si solo das acceso mientras la app está abierta, no se cuenta la distancia que recorres con la pantalla apagada, aunque el reloj sigue corriendo.',
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
};
