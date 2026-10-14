import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'invite-members-and-roles',
	title: 'Invitar a miembros y asignarles roles',
	summary: 'Comparte un enlace de invitación, aprueba solicitudes para unirse y asigna a miembros de confianza el rol de administrador, organizador de eventos o director de carrera.',
	sections: [
		{
			heading: 'Cómo se une la gente',
			blocks: [
				{
					type: 'p',
					text: 'Cómo se une alguien depende de la política de ingreso del club, que elegiste al crearlo y puedes cambiar con **Editar club** en la web.',
				},
				{
					type: 'list',
					items: [
						'**Cualquiera puede unirse**: la gente selecciona **Unirse al club** en la página del club y entra al instante.',
						'**Requiere aprobación**: la gente selecciona **Solicitar unirse** y espera en una cola hasta que un administrador la apruebe.',
						'**Solo por invitación**: la gente necesita un enlace de invitación de un administrador.',
					],
				},
			],
		},
		{
			heading: 'Compartir un enlace de invitación',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abre tu club en la web. Cuando el club es **Solo por invitación**, los administradores ven un panel **Enlace de invitación** en la página del club.',
						'Selecciona **Generar enlace de invitación** la primera vez y luego **Copiar** para copiar el enlace en el portapapeles.',
						'Envía el enlace como prefieras. Cualquiera que lo abra e inicie sesión se une al club como miembro.',
					],
				},
				{
					type: 'p',
					text: 'Si un enlace se ha difundido más de lo que querías, selecciona **Renovar**. Se crea un enlace nuevo y el antiguo deja de funcionar de inmediato.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Un enlace de invitación deja entrar directamente: se salta la cola de aprobación, así que compártelo solo con personas a las que estés dispuesto a admitir. Si el club exige el reconocimiento de los riesgos de la actividad, el enlace lo pide antes de dejar entrar a nadie.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'En la app del móvil, un miembro también puede tocar **Unirse con código de invitación** en la pestaña **Clubes** de **Social** y pegar el enlace entero o solo el código que va después de /clubs/join/. Abrir el enlace en el navegador del móvil también funciona.',
				},
			],
		},
		{
			heading: 'Aprobar o rechazar solicitudes para unirse',
			blocks: [
				{
					type: 'p',
					text: 'Cuando el club requiere aprobación, los administradores ven **Solicitudes pendientes** con un recuento al lado.',
				},
				{
					type: 'list',
					items: [
						'En la web, selecciona **Aprobar** o **Rechazar** en cada solicitud, o **Aprobar todas** cuando haya varias esperando. Al rechazar se te pide confirmación primero.',
						'En la app del móvil, abre la pestaña **Miembros** del club y toca **Aprobar** o **Rechazar** en cada solicitud.',
					],
				},
			],
		},
		{
			heading: 'Asignar un rol a los miembros',
			blocks: [
				{
					type: 'p',
					text: 'Cada club tiene un único **Propietario**, la persona que lo creó. Otras personas pueden tener uno de estos roles:',
				},
				{
					type: 'list',
					items: [
						'**Administrador**: cambia los ajustes del club, gestiona a los miembros y sus roles, dirige eventos y carreras, y aprueba resultados.',
						'**Organizador de eventos**: crea, edita y elimina eventos y añade asistentes, sin acceso a los ajustes del club ni a los miembros.',
						'**Director de carrera**: prepara, da la salida y finaliza carreras, y aprueba o rechaza resultados.',
						'**Miembro**: publica respuestas, confirma su asistencia a eventos y envía sus propios resultados de carrera.',
					],
				},
				{
					type: 'steps',
					items: [
						'Abre tu club en la web y elige la pestaña **Miembros**.',
						'Usa el menú de rol junto a un miembro para elegir su nuevo rol. El cambio se guarda al instante.',
						'Para sacar a alguien del club, usa el botón de quitar junto a esa persona y confirma.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Cambiar roles y quitar miembros solo se puede hacer en la web por ahora. La pestaña **Miembros** de la app del móvil muestra el número de miembros y las solicitudes pendientes, no la lista completa.',
				},
			],
		},
	],
	sources: {
		title: '7a795179c19e9ede',
		summary: '6bd8f063f9b47e9c',
		's0.heading': 'a0b11759509dec45',
		's0.b0': '6373b2a85a1609f6',
		's0.b1.i0': 'ee27e4b5847787d3',
		's0.b1.i1': 'b3ca923e10bea1a6',
		's0.b1.i2': '43f232607a69a9eb',
		's1.heading': 'ff3fad2f072540f7',
		's1.b0.i0': '53bc4c42c338a50b',
		's1.b0.i1': '527bae1b53082d53',
		's1.b0.i2': '7717031f30823ba7',
		's1.b1': '71a8c58fdf04e4c7',
		's1.b2': 'ac04b52b16128c47',
		's1.b3': '95001612b9e89408',
		's2.heading': 'ac0d31b6960aec87',
		's2.b0': '5e020c1365ade658',
		's2.b1.i0': '001fdb020367ef82',
		's2.b1.i1': '8a13349f6280affe',
		's3.heading': '5ae9577e9c45959a',
		's3.b0': '6b88528b0352a4ca',
		's3.b1.i0': '4a654fadcb92a4e9',
		's3.b1.i1': '4fb82402d20e5ae6',
		's3.b1.i2': '99c1319e71b4efe7',
		's3.b1.i3': 'd2c28cf99bce668b',
		's3.b2.i0': '8552b807ede6b519',
		's3.b2.i1': '12d66025f3fdd53b',
		's3.b2.i2': '2bc7dca0194195b4',
		's3.b3': '2dbf13356f8d50fe',
	},
};
