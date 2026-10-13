import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'privacy-zones',
	title: 'Esconder sua casa com zonas de privacidade',
	summary: 'Desenhe um círculo ao redor da sua casa, do trabalho ou de qualquer outro lugar para que o início e o fim das suas corridas e rotas dentro dele fiquem ocultos para todos, menos para você.',
	sections: [
		{
			heading: 'O que uma zona de privacidade faz',
			blocks: [
				{
					type: 'p',
					text: 'Uma zona de privacidade é um círculo no mapa. Quando uma corrida ou rota começa ou termina dentro de uma, essa parte do trajeto é cortada antes que qualquer outra pessoa a veja, então a linha parece começar e terminar na borda do círculo.',
				},
				{
					type: 'list',
					items: [
						'Ela vale para o que as outras pessoas veem: corridas e rotas compartilhadas, o seu perfil público, o feed, os mapas de calor e a página de acompanhamento ao vivo.',
						'Ela vale para as corridas que você já gravou e também para as novas, porque o trajeto é cortado toda vez que outra pessoa o visualiza.',
						'Você sempre vê o seu trajeto completo, e os arquivos que você exporta para si mesmo também mantêm o trajeto completo.',
					],
				},
			],
		},
		{
			heading: 'Adicionar uma zona na web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra [[route:/settings/privacy|Privacidade e compartilhamento]] em Configurações.',
						'Em **Zonas de privacidade**, selecione **Adicionar uma zona**.',
						'Clique no mapa onde a zona deve ficar centralizada, ou selecione **Usar localização atual**, e depois arraste o marcador para ajustar.',
						'Defina o **Raio**. Tudo dentro do círculo vermelho fica oculto dos compartilhamentos públicos.',
						'Selecione **Adicionar zona**. A zona é salva na hora.',
					],
				},
				{
					type: 'p',
					text: 'Para excluir uma zona, selecione **Remover** ao lado dela e confirme. Remover uma zona volta a mostrar aquela área nos compartilhamentos públicos.',
				},
			],
		},
		{
			heading: 'Adicionar uma zona no app para celular',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra a aba **Você**, depois **Preferências**, e em **Privacidade e compartilhamento** toque em **Zonas de privacidade**.',
						'Toque no mapa para colocar uma zona. Use **Buscar lugares…** ou **Localizar-me** para mover o mapa antes.',
						'Ajuste o controle deslizante **Raio**.',
						'Toque em **Salvar**. Nada muda até você salvar.',
					],
				},
				{
					type: 'p',
					text: 'Para excluir uma zona, toque no marcador dela e confirme, ou use **Limpar tudo** para remover todas as zonas de uma vez. Depois toque em **Salvar**; remover uma zona volta a mostrar aquela área nos compartilhamentos públicos.',
				},
			],
		},
		{
			heading: 'Como escolher uma boa zona',
			blocks: [
				{
					type: 'list',
					items: [
						'Centralize a zona perto da sua porta, e não exatamente nela, para que a borda do círculo não aponte direto para a sua casa.',
						'Faça a zona grande o bastante para cobrir algumas ruas. Um círculo pequeno demais ainda pode entregar onde você mora.',
						'Adicione uma para cada lugar de onde você costuma sair, como o trabalho ou a casa de um amigo.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'As zonas cortam apenas a linha no mapa. O título, a descrição e as fotos de uma corrida aparecem como você os escreveu, então não coloque endereços neles.',
				},
			],
		},
	],
	sources: {
		title: 'd9e7d40ed8ec1d93',
		summary: '04c4913e2da59def',
		's0.heading': '27ee9eff5654fc40',
		's0.b0': '0786f273bb90019e',
		's0.b1.i0': 'ae791e6bb37bf75e',
		's0.b1.i1': 'f895445f10db7b57',
		's0.b1.i2': '591dec4de03df2a3',
		's1.heading': 'cc3973572fe81b73',
		's1.b0.i0': 'a9f7c5a79d8779f0',
		's1.b0.i1': 'de234d8646b8454f',
		's1.b0.i2': '35c82b7aef764872',
		's1.b0.i3': '1d8fc63d18b8641a',
		's1.b0.i4': '150b03da903ccf27',
		's1.b1': 'b395019ec1836f1e',
		's2.heading': 'd50fe7d487cde78b',
		's2.b0.i0': '0f37a464ec66cdc7',
		's2.b0.i1': 'e3478863d167e8fe',
		's2.b0.i2': 'ca9cc061ff309425',
		's2.b0.i3': '2f1655078cb4ae12',
		's2.b1': 'cb30c404ac96aa57',
		's3.heading': 'ea3ab9efa7240662',
		's3.b0.i0': '9184e7f4329c71d3',
		's3.b0.i1': '7e6aff2443fca79b',
		's3.b0.i2': '2d441105a1624ed1',
		's3.b1': '20c32d436fe0799c',
	},
};
