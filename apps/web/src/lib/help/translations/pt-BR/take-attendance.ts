import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'take-attendance',
	title: 'Registrar a presença em uma aula',
	summary: 'Marque quem realmente veio a cada ocorrência de uma aula, separado de quem disse que viria, na web ou no app do celular.',
	sections: [
		{
			heading: 'Quem pode registrar, e onde',
			blocks: [
				{
					type: 'p',
					text: 'A presença é para eventos do tipo **Aula**, e só os administradores do clube e os organizadores do evento podem marcá-la. Funciona do mesmo jeito na web e no app do celular, então você pode fazer isso pelo celular, na frente da sala.',
				},
				{
					type: 'p',
					text: 'Ela é separada da confirmação de presença (RSVP). Alguém pode estar **Confirmado**, ou inscrito e com pagamento feito, e mesmo assim ser marcado como ausente; marcar a presença nunca altera a inscrição de ninguém nem reembolsa ninguém.',
				},
			],
		},
		{
			heading: 'Marcar quem veio',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra a aula. Se ela se repetir, use **Escolha uma ocorrência** para escolher a data de hoje, porque a presença é registrada por ocorrência.',
						'Role até a lista de participantes.',
						'Ao lado de cada pessoa, selecione **Marcar como presente** ou **Marcar como ausente**.',
						'Marcou o errado? Selecione o mesmo botão de novo para desfazer.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Você não precisa marcar todo mundo. Quem ficar sem marcação simplesmente não tem presença registrada.',
				},
			],
		},
		{
			heading: 'O que os outros veem',
			blocks: [
				{
					type: 'p',
					text: 'Outras pessoas que olham a aula veem um rótulo **Presente** ou **Ausente** ao lado de cada nome que você marcou, mas não podem alterá-lo.',
				},
				{
					type: 'p',
					text: 'A presença não adiciona a aula ao histórico de treinos de ninguém. Os participantes fazem isso por conta própria com **Registrar como treino** na página da aula, ou seguindo o plano de sessão da aula: veja [[guide:build-a-session-plan|Montar um plano de sessão]].',
				},
			],
		},
	],
	sources: {
		title: '8e94f2c520c4725e',
		summary: '19234d07e67c5a4f',
		's0.heading': 'faee9310c256dbe3',
		's0.b0': 'f196a1f6af265a97',
		's0.b1': '4e5ee5d97f6345cd',
		's1.heading': '606dabb8e1030b7c',
		's1.b0.i0': 'd74050897fbc9e6d',
		's1.b0.i1': '2d151dfb1f62d0b0',
		's1.b0.i2': 'aee700bc763c5ade',
		's1.b0.i3': '3222de96fadf77f6',
		's1.b1': '1ca4fbd7f7608965',
		's2.heading': '7e87e01018106f7c',
		's2.b0': '83dbaf9e7ca920df',
		's2.b1': '1195e880106739dc',
	},
};
