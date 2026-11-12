import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'private-profile-and-follow-requests',
	title: 'Tornar o seu perfil privado e aprovar seguidores',
	summary: 'Ative um perfil privado para que só os seguidores que aprovar vejam as suas corridas e aprove ou recuse os pedidos para seguir à medida que chegam.',
	sections: [
		{
			heading: 'O que um perfil privado esconde',
			blocks: [
				{
					type: 'p',
					text: 'Com um perfil privado, só os seguidores que aprovou veem as suas corridas e outras atividades, e as listas de quem o segue e de quem segue. As outras pessoas veem o seu nome, a sua fotografia e o número de seguidores, com **Este perfil é privado** no lugar das suas corridas.',
				},
				{
					type: 'list',
					items: [
						'As pessoas continuam a poder encontrá-lo pelo nome e pedir para o seguir. Para ficar também fora da pesquisa por nome, desative **Mostrar-me na pesquisa por nome** na mesma página.',
						'Quem já o segue quando ativa a opção continua a segui-lo.',
						'As rotas, os resultados de eventos e os emblemas mantêm a sua própria visibilidade, porque cada um é partilhado separadamente.',
						'Um link em direto que envie durante uma corrida, incluindo o link de um alerta de segurança, continua a funcionar para as pessoas a quem o enviou.',
					],
				},
			],
		},
		{
			heading: 'Ativar',
			blocks: [
				{
					type: 'steps',
					items: [
						'Na web, abra [[route:/settings/privacy|Privacidade e partilha]] nas Definições e marque **Perfil privado** em **Ser encontrado**.',
						'Na app do telemóvel, abra **Preferências** no separador **Tu** e ative **Perfil privado** em **Privacidade e partilha**.',
					],
				},
				{
					type: 'p',
					text: 'A alteração é guardada de imediato.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Se voltar a desativá-lo, todos os pedidos ainda pendentes são aprovados e essas pessoas passam logo a segui-lo.',
				},
			],
		},
		{
			heading: 'Aprovar ou recusar pedidos',
			blocks: [
				{
					type: 'p',
					text: 'Quando alguém pede para o seguir, recebe uma notificação. Os pedidos para seguir contam como importantes, por isso, por predefinição, também os recebe por e-mail e por push.',
				},
				{
					type: 'steps',
					items: [
						'Abra a notificação. Também pode selecionar **Ver pedidos para seguir** em **Perfil privado** na web, ou tocar em **Pedidos para seguir** em **Perfil privado** na app do telemóvel.',
						'Escolha **Aprovar** para que essa pessoa veja o seu perfil, ou **Recusar** para rejeitar o pedido. A pessoa não é avisada quando recusa.',
					],
				},
			],
		},
		{
			heading: 'Seguir alguém com perfil privado',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o perfil dessa pessoa e escolha **Pedir para seguir**.',
						'Enquanto espera, o botão mostra **Pedido enviado**. Escolha-o de novo para retirar o pedido.',
						'Quando a pessoa aprovar, o botão mostra **A seguir** e as corridas dela aparecem.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se deixar de seguir alguém com perfil privado, tem de voltar a pedir para ver as corridas dessa pessoa.',
				},
			],
		},
	],
	sources: {
		title: '55db0776dec72032',
		summary: 'e6bdb709c41db3db',
		's0.heading': '7237eeb5591555f6',
		's0.b0': '7c2c985869ef044e',
		's0.b1.i0': '46be0ce6681dea88',
		's0.b1.i1': 'a724eac62d2e2309',
		's0.b1.i2': 'ab64bd2163f3b938',
		's0.b1.i3': '3b0697b82ce30a11',
		's1.heading': 'e679ca0953315c31',
		's1.b0.i0': '8f81f66ef4f33b7f',
		's1.b0.i1': 'a2257970d4c18f57',
		's1.b1': '0a095b7bf566bcfd',
		's1.b2': 'ad288ebf5f9c8856',
		's2.heading': '93f13a5ed9bf1a93',
		's2.b0': 'd2a27163d9554bb2',
		's2.b1.i0': '2ed84578bbbb7b5f',
		's2.b1.i1': '6d2ff83c41b08bdc',
		's3.heading': '185850fe604d3b78',
		's3.b0.i0': 'd39f871565375e15',
		's3.b0.i1': 'd9de093774b97d75',
		's3.b0.i2': 'e44b708377c7377a',
		's3.b1': '6f8889c46cf20f3c',
	},
};
