import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'notifications-reactions-and-mentions',
	title: 'Reações, menções e as suas notificações',
	summary: 'Reaja a corridas, goste de comentários e mencione outros corredores, e escolha que notificações também lhe chegam por e-mail e ao telemóvel.',
	sections: [
		{
			heading: 'Reagir, gostar e mencionar',
			blocks: [
				{
					type: 'list',
					items: [
						'Na corrida de outra pessoa, junto aos kudos, escolha uma reação: **Em grande**, **Forte**, **Campeão**, **Muito bem** ou **Olá**. Pode deixar mais do que uma, e escolher de novo uma reação retira-a.',
						'Para gostar de um comentário, escolha o coração ao lado. Não pode reagir à sua própria corrida nem gostar do seu próprio comentário.',
						'Para mencionar alguém num comentário, escreva @ e o início do nome, e escolha a pessoa na lista que aparece. Só é avisada se já puder ver a corrida e nenhuma das duas pessoas tiver bloqueado a outra.',
					],
				},
				{
					type: 'p',
					text: 'As reações e os gostos nos comentários aparecem na própria corrida. Os cartões do feed continuam a mostrar apenas o número de kudos e de comentários.',
				},
			],
		},
		{
			heading: 'Onde aparecem as notificações',
			blocks: [
				{
					type: 'p',
					text: 'Todas as notificações chegam à app: no sino, na web, e no separador **Notificações** do seu perfil, na app do telemóvel. É o próprio que decide se também lhe chegam por e-mail ou ao telemóvel.',
				},
			],
		},
		{
			heading: 'Escolher o que é enviado por e-mail e push',
			blocks: [
				{
					type: 'steps',
					items: [
						'Na web, abra [[route:/settings/notifications|Notificações]] nas Definições. Na app do telemóvel, abra **Preferências** no separador **Tu** e desloque-se até **Notificações**.',
						'Defina **Notificações por e-mail** e **Notificações push** em separado.',
					],
				},
				{
					type: 'list',
					items: [
						'**Apenas importantes**, a predefinição: aquilo de que está à espera ou que muda os seus planos, como mensagens, lembretes e cancelamentos de eventos, um lugar reservado para si numa lista de espera, menções, pedidos para seguir e uma exportação de dados concluída.',
						'**Todas**: as importantes e ainda as sociais, como kudos, comentários, novos seguidores, reações e gostos nos comentários.',
						'**Desativadas**: nada nesse canal. A app continua a mostrar tudo.',
					],
				},
			],
		},
		{
			heading: 'Desativar um único tipo',
			blocks: [
				{
					type: 'p',
					text: 'Na web, a mesma página permite silenciar alguns tipos sem mudar um canal inteiro: **Exportação de dados pronta**, **Menções**, **Reações às minhas corridas**, **Gostos nos meus comentários** e **Pedidos para seguir**. Desmarque um e deixa de ser enviado por e-mail e push, também no telemóvel, mas continua a aparecer na app.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Estas opções só servem para desligar. As reações e os gostos nos comentários só são enviados quando um canal está em **Todas**, e um canal em **Desativadas** fica em silêncio, independentemente das opções.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Por agora, as opções por tipo só existem na web. A app do telemóvel mostra as definições de e-mail e push.',
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
