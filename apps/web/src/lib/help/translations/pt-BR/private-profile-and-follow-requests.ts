import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'private-profile-and-follow-requests',
	title: 'Deixar seu perfil privado e aprovar seguidores',
	summary: 'Ative um perfil privado para que só os seguidores que você aprova vejam suas corridas e aprove ou recuse as solicitações para seguir conforme elas chegam.',
	sections: [
		{
			heading: 'O que um perfil privado esconde',
			blocks: [
				{
					type: 'p',
					text: 'Com um perfil privado, só os seguidores que você aprovou veem suas corridas e outras atividades, e as listas de quem segue você e de quem você segue. As outras pessoas veem seu nome, sua foto e suas contagens de seguidores, com **Este perfil é privado** no lugar das suas corridas.',
				},
				{
					type: 'list',
					items: [
						'As pessoas ainda podem encontrar você pelo nome e pedir para seguir. Para ficar fora da busca por nome também, desative **Exibir-me na busca por nome** na mesma página.',
						'Quem já segue você quando você ativa a opção continua seguindo.',
						'Rotas, resultados de eventos e emblemas mantêm a própria visibilidade, porque cada um é compartilhado separadamente.',
						'Um link ao vivo que você envia durante uma corrida, incluindo o link de um alerta de segurança, continua funcionando para quem o recebeu.',
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
						'Na web, abra [[route:/settings/privacy|Privacidade e compartilhamento]] em Configurações e marque **Perfil privado** em **Ser encontrado**.',
						'No app para celular, abra **Preferências** na aba **Você** e ative **Perfil privado** em **Privacidade e compartilhamento**.',
					],
				},
				{
					type: 'p',
					text: 'A mudança é salva na hora.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Desativar de novo aprova todas as solicitações ainda pendentes, e essas pessoas passam a seguir você na hora.',
				},
			],
		},
		{
			heading: 'Aprovar ou recusar solicitações',
			blocks: [
				{
					type: 'p',
					text: 'Quando alguém pede para seguir você, você recebe uma notificação. As solicitações para seguir contam como importantes, então, por padrão, elas também chegam por e-mail e por push.',
				},
				{
					type: 'steps',
					items: [
						'Abra a notificação. Você também pode selecionar **Ver solicitações para seguir** em **Perfil privado** na web, ou tocar em **Solicitações para seguir** em **Perfil privado** no app para celular.',
						'Escolha **Aprovar** para que essa pessoa veja seu perfil, ou **Recusar** para negar a solicitação. A pessoa não é avisada quando você recusa.',
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
						'Abra o perfil da pessoa e escolha **Pedir para seguir**.',
						'Enquanto você espera, o botão mostra **Solicitado**. Escolha-o de novo para retirar a solicitação.',
						'Quando a pessoa aprovar, o botão mostra **Seguindo** e as corridas dela aparecem.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se você deixar de seguir alguém com perfil privado, vai precisar pedir de novo para ver as corridas dessa pessoa.',
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
