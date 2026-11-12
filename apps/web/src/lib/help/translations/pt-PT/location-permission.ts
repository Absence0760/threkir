import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'location-permission',
	title: 'Acesso à localização para registar corridas',
	summary: 'Que opção de localização escolher no Android e no iPhone, o que cada uma muda nas suas corridas e como alterá-la mais tarde nas definições.',
	sections: [
		{
			heading: 'Porque é que a app pede a sua localização',
			blocks: [
				{
					type: 'p',
					text: 'A sua localização desenha o mapa de uma corrida e mede a distância e o ritmo. Sem ela, a corrida continua a registar tempo e passos, mas sem mapa, distância ou ritmo.',
				},
				{
					type: 'p',
					text: 'O pedido surge durante a configuração: depois da página **Acesso à localização**, tocar em **Conceder permissão** abre o pedido do seu telemóvel. Se recusar, a app avisa-o e propõe **Abrir definições**. Se ainda não tiver dado acesso quando tocar em **INICIAR**, o telemóvel pode voltar a perguntar.',
				},
			],
		},
		{
			heading: 'No Android',
			blocks: [
				{
					type: 'p',
					text: 'O primeiro pedido do Android só pode dar acesso enquanto a app está a ser utilizada. Para a corrida continuar a ser seguida com o ecrã desligado, é preciso **Permitir sempre**, e o Android só deixa escolher essa opção nas definições.',
				},
				{
					type: 'steps',
					items: [
						'No pedido, deixe **Precisa** selecionada e toque em **Enquanto estiver a utilizar a app**.',
						'Antes da sua primeira corrida, a app mostra **Permitir sempre a localização**. Toque em **Abrir definições**.',
						'Em **Autorizações**, toque em **Localização**, escolha **Permitir sempre** e depois volte à app.',
					],
				},
				{
					type: 'p',
					text: 'Se tocar em **Iniciar mesmo assim**, a corrida é registada normalmente enquanto a app estiver no ecrã. Com o ecrã desligado ou noutra app, o Android pode deixar de enviar a sua localização: o tempo continua a contar e nada do que já foi registado se perde, mas a distância percorrida entretanto não é contabilizada. Quando isso acontece, ao voltar surge uma mensagem que começa por **O registo foi pausado enquanto esteve fora**, com um botão **Definições**.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'O aviso antes de uma corrida aparece uma única vez. Só volta se tiver permitido o acesso sempre e esse acesso tiver sido retirado mais tarde, por exemplo quando o Android repõe as autorizações das apps que não abre há algum tempo.',
				},
				{
					type: 'list',
					items: [
						'Com **Aproximada**, a localização é demasiado imprecisa para medir uma corrida: verá **Localização aproximada — distância pausada** durante toda a corrida.',
						'**Apenas desta vez** vale para a corrida que vai iniciar, e da próxima vez o telemóvel volta a perguntar.',
						'Com **Não permitir**, as corridas registam apenas tempo e passos.',
					],
				},
			],
		},
		{
			heading: 'No iPhone',
			blocks: [
				{
					type: 'p',
					text: 'No iPhone, o acesso durante a utilização da app é suficiente: a corrida continua a ser registada com o ecrã bloqueado ou enquanto utiliza outra app. A app nunca pede **Sempre**, e não precisa dessa opção.',
				},
				{
					type: 'steps',
					items: [
						'No pedido, toque em **Permitir durante a utilização da app**.',
						'Deixe a localização exata ativada no pedido. Sem ela, a sua posição fica demasiado imprecisa para medir a distância, e a corrida mostra **Localização aproximada — distância pausada**.',
					],
				},
				{
					type: 'p',
					text: '**Permitir uma vez** vale apenas para esta corrida, e da próxima vez o iPhone volta a perguntar. Com **Não permitir**, as corridas registam apenas tempo e passos.',
				},
			],
		},
		{
			heading: 'Poupança de bateria',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Alguns telemóveis Android (Samsung, Xiaomi, OnePlus e outros) põem as apps a dormir para poupar bateria, o que pode interromper o registo de uma corrida longa com o ecrã desligado, mesmo com **Permitir sempre**. Antes da sua primeira corrida, a app mostra uma vez **Manter a gravação ativa em segundo plano**: toque em **Abrir definições** e exclua o Threkir da otimização da bateria. Se tocou em **Agora não**, abra a página da app nas definições do telemóvel, toque em **Bateria** e escolha **Sem restrições**. Os nomes variam um pouco de fabricante para fabricante.',
				},
			],
		},
		{
			heading: 'Alterar mais tarde',
			blocks: [
				{
					type: 'p',
					text: 'No Android:',
				},
				{
					type: 'steps',
					items: [
						'Abra as **Definições** do telemóvel e toque em **Apps** e depois em **Threkir**.',
						'Toque em **Autorizações** e depois em **Localização**.',
						'Escolha **Permitir sempre** e ative **Usar localização exata**.',
					],
				},
				{
					type: 'p',
					text: 'No iPhone:',
				},
				{
					type: 'steps',
					items: [
						'Abra **Definições** › **Privacidade e Segurança** › **Serviços de Localização** e confirme que os **Serviços de Localização** estão ativados.',
						'Toque em **Threkir** e escolha **Durante a utilização da app**.',
						'Ative **Localização exata**.',
					],
				},
				{
					type: 'p',
					text: 'Se a localização estiver desativada ou bloqueada quando iniciar uma corrida, o ecrã de corrida avisa-o, e o botão **Definições** desse ecrã leva-o ao sítio certo.',
				},
			],
		},
		{
			heading: 'O que a app faz com a sua localização',
			blocks: [
				{
					type: 'list',
					items: [
						'Lê a sua localização enquanto regista uma corrida e quando um mapa se centra em si, por exemplo ao criar um percurso ou ao colocar uma zona de privacidade. Não o segue entre corridas.',
						'No Android, surge uma notificação enquanto uma corrida está a ser registada, se permitir notificações.',
						'O traçado de uma corrida fica no seu telemóvel até ser sincronizado com a sua conta ou até o partilhar, e quem o pode ver segue as suas definições de privacidade: veja [[guide:your-data-and-privacy|os seus dados e a sua privacidade]].',
						'Para esconder onde mora, configure [[guide:privacy-zones|zonas de privacidade]]. A sua posição em direto só é partilhada se ativar o [[guide:live-tracking-and-safety|seguimento em direto]].',
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
		's1.b4.i0': '9c6c79a701984fae',
		's1.b4.i1': 'd35c46ecb6f1579e',
		's1.b4.i2': '09d7ce333fe83b8c',
		's2.heading': '873081b6807b4197',
		's2.b0': '6912b4c52f4c4037',
		's2.b1.i0': '302121c948975146',
		's2.b1.i1': '5776de36117755b3',
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
