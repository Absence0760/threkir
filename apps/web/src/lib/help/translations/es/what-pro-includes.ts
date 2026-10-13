import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'what-pro-includes',
	source: 'd06d482fd22c314b',
	title: 'Qué incluye Pro',
	summary: 'Todas las pantallas de Threkir son gratuitas; Pro amplía tu cupo del Entrenador IA y adelanta en la cola parte del trabajo en segundo plano.',
	sections: [
		{
			heading: 'Lo que sigue siendo gratis',
			blocks: [
				{
					type: 'p',
					text: 'Nada en la app está bloqueado tras Pro. Las cuentas gratuitas tienen grabación ilimitada en el móvil y el reloj, rutas, planes de entrenamiento y las cifras que los sustentan, clubes y eventos, el feed social, contactos de seguridad, importaciones y copias de seguridad.',
				},
			],
		},
		{
			heading: 'Lo que añade Pro',
			blocks: [
				{
					type: 'list',
					items: [
						'**Coach IA — 10/día**: diez mensajes al día al Entrenador IA en lugar de dos. El recuento se reinicia a medianoche UTC.',
						'Respuestas del Entrenador IA más largas y completas, que pueden tener en cuenta más de tus carreras.',
						'**Map-matching prioritario**: tus trazas GPS se ajustan a las calles antes que las de las cuentas gratuitas, así que están listas antes.',
						'**Exportaciones a la nube prioritarias**: hasta 8 exportaciones de paquetes GPX por hora en lugar de 2.',
						'**Generación de rutas en el servidor**: bucles trazados sobre la red de calles real cuando generas una ruta por distancia. Las cuentas gratuitas siguen teniendo generación de bucles, calculada en el navegador.',
						'Descripciones de rutas más ricas: en la página de una ruta, **Mejorar con IA** convierte la descripción estándar en un párrafo más completo.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Algunas de estas funciones dependen de servicios que puede que aún no estén activados. La tarjeta Pro de [[route:/settings/upgrade|Pro y apoyo]] solo muestra lo que funciona hoy; si dice **Pro desbloquea el entrenador con IA: próximamente.**, todavía no se puede comprar Pro.',
				},
			],
		},
		{
			heading: 'Cómo conseguir Pro',
			blocks: [
				{
					type: 'p',
					text: 'Pro es una suscripción mensual o anual; la tarjeta Pro muestra los precios actuales. Dónde puedes comprarla depende de tu dispositivo:',
				},
				{
					type: 'list',
					items: [
						'En un iPhone, abre **Pro y apoyo** en la pestaña **Tú** y suscríbete a través del App Store.',
						'En la web, abre [[route:/settings/upgrade|Pro y apoyo]] en Configuración. Si dice **La suscripción desde la web llegará pronto.**, suscríbete en la app de iPhone.',
					],
				},
				{
					type: 'p',
					text: 'Pro va asociado a tu cuenta, no a tu dispositivo, así que una suscripción comprada en un dispositivo funciona en todos aquellos en los que inicies sesión.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Los precios están en dólares estadounidenses, y el App Store cobra el precio fijado para tu país. Nuestro procesador de pagos no puede dar servicio a algunos países y métodos de pago.',
				},
			],
		},
		{
			heading: 'Gestionar o cancelar',
			blocks: [
				{
					type: 'list',
					items: [
						'Cancela o cambia tu plan donde lo contrataste: el App Store, Play Store o el portal de facturación web. **Gestionar suscripción** te lleva allí.',
						'En un móvil nuevo, toca **Restaurar compras** en **Pro y apoyo** para recuperar una suscripción existente.',
						'¿Prefieres hacer una aportación puntual? **Donar** está en la misma página.',
					],
				},
			],
		},
	],
};
