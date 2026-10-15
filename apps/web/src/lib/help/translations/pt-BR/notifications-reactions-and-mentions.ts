import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'notifications-reactions-and-mentions',
	title: 'Reações, menções e suas notificações',
	summary: 'Reaja a corridas, curta comentários e mencione outros corredores, e escolha quais notificações também chegam ao seu e-mail e ao seu celular.',
	sections: [
		{
			heading: 'Reagir, curtir e mencionar',
			blocks: [
				{
					type: 'list',
					items: [
						'Na corrida de outra pessoa, ao lado dos kudos, escolha uma reação: **Pegando fogo**, **Forte**, **Campeão**, **Mandou bem** ou **Oi**. Você pode deixar mais de uma, e escolher de novo uma reação a remove.',
						'Para curtir um comentário, escolha o coração ao lado dele. Você não pode reagir à sua própria corrida nem curtir o seu próprio comentário.',
						'Para mencionar alguém em um comentário, digite @ e o começo do nome, e escolha a pessoa na lista que aparece. Ela só é avisada se já puder ver a corrida e nenhum de vocês tiver bloqueado o outro.',
					],
				},
				{
					type: 'p',
					text: 'As reações e as curtidas em comentários aparecem na própria corrida. Os cards do feed continuam mostrando só o número de kudos e de comentários.',
				},
			],
		},
		{
			heading: 'Onde as notificações aparecem',
			blocks: [
				{
					type: 'p',
					text: 'Toda notificação chega ao app: no sino, na web, e na aba **Notificações** do seu perfil, no app para celular. Você decide se ela também chega ao seu e-mail ou ao seu celular.',
				},
			],
		},
		{
			heading: 'Escolher o que vai por e-mail e push',
			blocks: [
				{
					type: 'steps',
					items: [
						'Na web, abra [[route:/settings/notifications|Notificações]] em Configurações. No app para celular, abra **Preferências** na aba **Você** e role até **Notificações**.',
						'Defina **Notificações por e-mail** e **Notificações push** separadamente.',
					],
				},
				{
					type: 'list',
					items: [
						'**Apenas importantes**, o padrão: o que você está esperando ou o que muda seus planos, como mensagens, lembretes e cancelamentos de eventos, uma vaga reservada para você em uma lista de espera, menções, solicitações para seguir e uma exportação de dados concluída.',
						'**Todas**: as importantes e também as sociais, como kudos, comentários, novos seguidores, reações e curtidas em comentários.',
						'**Desativadas**: nada nesse canal. O app continua mostrando tudo.',
					],
				},
			],
		},
		{
			heading: 'Desativar um único tipo',
			blocks: [
				{
					type: 'p',
					text: 'Na web, a mesma página permite silenciar alguns tipos sem mudar um canal inteiro: **Exportação de dados pronta**, **Menções**, **Reações às minhas corridas**, **Curtidas nos meus comentários** e **Solicitações para seguir**. Desmarque um e ele deixa de ir por e-mail e push, inclusive no celular, mas continua aparecendo no app.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Essas opções só desligam. Reações e curtidas em comentários só são enviadas quando um canal está em **Todas**, e um canal em **Desativadas** fica em silêncio, não importa o que as opções digam.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Por enquanto, as opções por tipo só existem na web. O app para celular mostra as configurações de e-mail e push.',
				},
			],
		},
	],
	sources: {
		title: 'e2dd210eef629161',
		summary: 'e3caa3dd4051e339',
		's0.heading': 'e9a0aa732a34f472',
		's0.b0.i0': '593bf97b7d4b2620',
		's0.b0.i1': '47c9a6dbdeb3921f',
		's0.b0.i2': '3f6f5a25189cef93',
		's0.b1': 'a9ec227602fcdf51',
		's1.heading': '074e9ceb824efc1f',
		's1.b0': '93884f29ad0c80fc',
		's2.heading': 'effb878df9e1a9ea',
		's2.b0.i0': '1c0dfd20d4a186e9',
		's2.b0.i1': '5a887c760fb14d6f',
		's2.b1.i0': '3adf3c1bbb3ad28d',
		's2.b1.i1': '20670a8e203c8f76',
		's2.b1.i2': '0e68d1c319340628',
		's3.heading': '99fb6c0af9167c4d',
		's3.b0': 'f6afa349950bc135',
		's3.b1': '17f7f798ca3f2b0d',
		's3.b2': '7471f8039fdd65e1',
	},
};
