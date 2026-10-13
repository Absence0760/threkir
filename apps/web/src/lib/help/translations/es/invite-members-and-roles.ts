import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'invite-members-and-roles',
	source: '1140e414e73d9132',
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
};
