import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'take-attendance',
	title: 'Registar presenças numa aula',
	summary: 'Marque quem veio realmente a cada ocorrência de uma aula, separadamente de quem disse que vinha, na web ou na app do telemóvel.',
	sections: [
		{
			heading: 'Quem pode registar e onde',
			blocks: [
				{
					type: 'p',
					text: 'As presenças aplicam-se a eventos do tipo **Aula**, e só os administradores e organizadores de eventos do clube as podem marcar. Funciona da mesma forma na web e na app do telemóvel, por isso pode fazê-lo a partir do telemóvel, à frente da sala.',
				},
				{
					type: 'p',
					text: 'É independente da confirmação de presença. Alguém pode estar **Confirmado**, ou inscrito e com pagamento feito, e mesmo assim ser marcado como ausente; marcar presenças nunca altera a inscrição de ninguém nem reembolsa ninguém.',
				},
			],
		},
		{
			heading: 'Marcar quem veio',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra a aula. Se se repetir, use **Escolha uma ocorrência** para escolher a data de hoje, porque as presenças são registadas por ocorrência.',
						'Desloque-se até à lista de participantes.',
						'Junto a cada pessoa, prima **Marcar como presente** ou **Marcar como ausente**.',
						'Premiu o botão errado? Prima o mesmo botão outra vez para limpar a marcação.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Não tem de marcar toda a gente. Quem ficar por marcar simplesmente não tem presença registada.',
				},
			],
		},
		{
			heading: 'O que os outros veem',
			blocks: [
				{
					type: 'p',
					text: 'As outras pessoas que consultam a aula veem uma etiqueta **Presente** ou **Ausente** junto a cada nome que marcou, mas não a podem alterar.',
				},
				{
					type: 'p',
					text: 'As presenças não acrescentam a aula ao histórico de treino de ninguém. Os participantes fazem-no eles próprios com **Registar como treino** na página da aula, ou ao seguir o plano de sessão da aula: consulte [[guide:build-a-session-plan|Criar um plano de sessão]].',
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
