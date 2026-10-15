import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'location-permission',
	title: 'Acesso à localização para gravar corridas',
	summary: 'Qual opção de localização escolher no Android e no iPhone, o que cada uma muda nas suas corridas e como alterá-la depois nas configurações.',
	sections: [
		{
			heading: 'Por que o app pede sua localização',
			blocks: [
				{
					type: 'p',
					text: 'Sua localização desenha o mapa de uma corrida e mede a distância e o ritmo. Sem ela, a corrida continua registrando tempo e passos, mas sem mapa, distância ou ritmo.',
				},
				{
					type: 'p',
					text: 'O pedido aparece durante a configuração: depois da página **Acesso à localização**, tocar em **Conceder permissão** abre a solicitação do seu celular. Se você recusar, o app avisa e oferece **Abrir configurações**. Se você ainda não tiver permitido quando tocar em **INICIAR**, o celular pode perguntar de novo.',
				},
			],
		},
		{
			heading: 'No Android',
			blocks: [
				{
					type: 'p',
					text: 'A primeira solicitação do Android só pode dar acesso durante o uso do app. Para a corrida continuar sendo rastreada com a tela desligada, é preciso **Permitir o tempo todo**, e o Android só deixa escolher isso nas configurações.',
				},
				{
					type: 'steps',
					items: [
						'Na solicitação, deixe **Precisa** selecionada e toque em **Durante o uso do app**.',
						'Antes da sua primeira corrida, o app mostra **Permitir localização o tempo todo**. Toque em **Abrir configurações**.',
						'Em **Permissões**, toque em **Localização**, escolha **Permitir o tempo todo** e depois volte ao app.',
					],
				},
				{
					type: 'p',
					text: 'Se você tocar em **Iniciar mesmo assim**, a corrida é gravada normalmente enquanto o app estiver na tela. Com a tela desligada ou em outro app, o Android pode parar de enviar sua localização: o tempo continua correndo e nada do que já foi gravado se perde, mas a distância percorrida nesse período não é contada. Quando isso acontece, ao voltar aparece uma mensagem que começa com **O rastreamento pausou enquanto você esteve fora**, com um botão **Configurações**.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'O aviso antes de uma corrida aparece uma vez só. Ele só volta se você tiver permitido o acesso o tempo todo e esse acesso for removido depois, por exemplo quando o Android redefine as permissões de apps que você não abre há algum tempo.',
				},
				{
					type: 'list',
					items: [
						'Com **Aproximada**, a localização é imprecisa demais para medir uma corrida: você verá **GPS fraco — distância pausada** durante toda a corrida.',
						'**Apenas esta vez** vale para a corrida que você vai começar, e na próxima vez o celular pergunta de novo.',
						'Com **Não permitir**, as corridas registram só tempo e passos.',
					],
				},
			],
		},
		{
			heading: 'No iPhone',
			blocks: [
				{
					type: 'p',
					text: 'No iPhone, o acesso durante o uso do app basta: a corrida continua sendo gravada com a tela bloqueada ou enquanto você usa outro app. O app nunca pede **Sempre**, e você não precisa disso.',
				},
				{
					type: 'steps',
					items: [
						'Na solicitação, toque em **Permitir Durante o Uso do App**.',
						'Deixe a localização precisa ativada na solicitação. Sem ela, sua posição fica imprecisa demais para medir a distância, e a corrida mostra **GPS fraco — distância pausada**.',
					],
				},
				{
					type: 'p',
					text: '**Permitir Uma Vez** vale só para esta corrida, e na próxima vez o iPhone pergunta de novo. Com **Não Permitir**, as corridas registram só tempo e passos.',
				},
			],
		},
		{
			heading: 'Economia de bateria',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Alguns celulares Android (Samsung, Xiaomi, OnePlus e outros) colocam os apps para dormir para economizar bateria, o que pode interromper a gravação de uma corrida longa com a tela desligada, mesmo com **Permitir o tempo todo**. Antes da sua primeira corrida, o app mostra uma vez **Manter a gravação ativa em segundo plano**: toque em **Abrir configurações** e exclua o Threkir da otimização de bateria. Se você tocou em **Agora não**, abra a página do app nas configurações do celular, toque em **Bateria** e escolha **Sem restrições**. Os nomes variam um pouco de fabricante para fabricante.',
				},
			],
		},
		{
			heading: 'Alterar depois',
			blocks: [
				{
					type: 'p',
					text: 'No Android:',
				},
				{
					type: 'steps',
					items: [
						'Abra as **Configurações** do celular e toque em **Apps** e depois em **Threkir**.',
						'Toque em **Permissões** e depois em **Localização**.',
						'Escolha **Permitir o tempo todo** e ative **Usar local exato**.',
					],
				},
				{
					type: 'p',
					text: 'No iPhone:',
				},
				{
					type: 'steps',
					items: [
						'Abra **Ajustes** › **Privacidade e Segurança** › **Serviços de Localização** e confira se **Serviços de Localização** está ativado.',
						'Toque em **Threkir** e escolha **Durante o Uso do App**.',
						'Ative **Localização Precisa**.',
					],
				},
				{
					type: 'p',
					text: 'Se a localização estiver desativada ou bloqueada quando você iniciar uma corrida, a tela de corrida avisa, e o botão **Configurações** dela leva você ao lugar certo.',
				},
			],
		},
		{
			heading: 'O que o app faz com sua localização',
			blocks: [
				{
					type: 'list',
					items: [
						'Ele lê sua localização enquanto você grava uma corrida e quando um mapa se centraliza em você, como ao criar uma rota ou posicionar uma zona de privacidade. Ele não segue você entre as corridas.',
						'No Android, uma notificação aparece enquanto uma corrida está sendo gravada, se você permitir notificações.',
						'O trajeto de uma corrida fica no seu celular até ser sincronizado com sua conta ou até você compartilhá-lo, e quem pode vê-lo segue suas configurações de privacidade: veja [[guide:your-data-and-privacy|seus dados e sua privacidade]].',
						'Para esconder onde você mora, configure [[guide:privacy-zones|zonas de privacidade]]. Sua posição ao vivo só é compartilhada se você ativar o [[guide:live-tracking-and-safety|rastreamento ao vivo]].',
					],
				},
			],
		},
	],
	sources: {
		'title': '583816a170012c19',
		'summary': '56769a6e224ff156',
		's0.heading': '794b04c19c7668d8',
		's0.b0': 'af2524b060ff7e41',
		's0.b1': 'c4efda4e34e087e7',
		's1.heading': 'd085d4c0606e9a65',
		's1.b0': 'f87947ee024ca95d',
		's1.b1.i0': '74eca884f8eb053b',
		's1.b1.i1': 'bc08250477141230',
		's1.b1.i2': 'cd926bc8428f270d',
		's1.b2': '3f9237c89f00534f',
		's1.b3': '6c15e5f41c0dbad5',
		's1.b4.i0': '96fb29287371ef73',
		's1.b4.i1': 'd35c46ecb6f1579e',
		's1.b4.i2': '09d7ce333fe83b8c',
		's2.heading': '873081b6807b4197',
		's2.b0': '6912b4c52f4c4037',
		's2.b1.i0': '302121c948975146',
		's2.b1.i1': '7bcc2b01bf8a35ab',
		's2.b2': 'dd5515e417bcce18',
		's3.heading': 'd91eca07ad12c491',
		's3.b0': '5ecc6e3ad1cacf65',
		's4.heading': '8489bd921c93cd06',
		's4.b0': '8a324e6ccca0ee87',
		's4.b1.i0': '682f9bd3caa2bb73',
		's4.b1.i1': '8cad8da0c6d30e3e',
		's4.b1.i2': '007cea366706e1e4',
		's4.b2': '1eb507e8f5d10b2b',
		's4.b3.i0': '29ad09bb32235340',
		's4.b3.i1': '54f8b50ec24d5250',
		's4.b3.i2': '4bbab96422f563b9',
		's4.b4': '20e869463ad7c51c',
		's5.heading': '11a805eb39c14582',
		's5.b0.i0': 'e4acbdfc462c84a6',
		's5.b0.i1': '1a49253f9adf5652',
		's5.b0.i2': '79d0adcf35c722c0',
		's5.b0.i3': 'f79c6d8e7f96a30f',
	},
};
