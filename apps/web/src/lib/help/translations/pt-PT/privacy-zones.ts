import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'privacy-zones',
	title: 'Esconder a sua casa com zonas de privacidade',
	summary: 'Desenhe um círculo à volta de casa, do trabalho ou de qualquer outro sítio para que o início e o fim das corridas e rotas dentro dele fiquem ocultos para todos menos para si.',
	sections: [
		{
			heading: 'O que faz uma zona de privacidade',
			blocks: [
				{
					type: 'p',
					text: 'Uma zona de privacidade é um círculo no mapa. Quando uma corrida ou rota começa ou termina dentro de uma, essa parte do trajeto é cortada antes de qualquer outra pessoa a ver, por isso a linha parece começar e terminar na orla do círculo.',
				},
				{
					type: 'list',
					items: [
						'Aplica-se ao que as outras pessoas veem: corridas e rotas partilhadas, o seu perfil público, o feed, os mapas de calor, a página de acompanhamento em direto e os mapas de corrida que um treinador com quem trabalha pode abrir.',
						'Aplica-se às corridas que já gravou, e não só às novas, porque o trajeto é cortado sempre que outra pessoa o vê.',
						'Vê sempre o seu trajeto completo, e os ficheiros que exporta para si também mantêm o trajeto completo.',
					],
				},
				{
					type: 'illustration',
					id: 'privacy-zones',
					alt: 'Uma linha de percurso começa numa casa dentro de um círculo. A parte dentro do círculo fica oculta para as outras pessoas, por isso a linha que veem começa na borda do círculo.',
				},
			],
		},
		{
			heading: 'Adicionar uma zona na web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra [[route:/settings/privacy|Privacidade e partilha]] nas Definições.',
						'Em **Zonas de privacidade**, selecione **Adicionar uma zona**.',
						'Clique no mapa onde a zona deve ficar centrada, ou selecione **Utilizar localização atual**, e depois arraste o marcador para afinar a posição.',
						'Defina o **Raio**. Tudo o que estiver dentro do círculo vermelho fica oculto nas partilhas públicas.',
						'Selecione **Adicionar zona**. A zona é guardada de imediato.',
					],
				},
				{
					type: 'p',
					text: 'Para eliminar uma zona, selecione **Remover** ao lado dela e confirme. Remover uma zona volta a mostrar essa área nas partilhas públicas.',
				},
			],
		},
		{
			heading: 'Adicionar uma zona na app do telemóvel',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o separador **Tu**, depois **Preferências** e, em **Privacidade e partilha**, toque em **Zonas de privacidade**.',
						'Toque no mapa para colocar uma zona. Use **Procurar lugares…** ou **Localizar-me** para mover o mapa primeiro.',
						'Ajuste o controlo deslizante **Raio**.',
						'Toque em **Guardar**. Nada muda até guardar.',
					],
				},
				{
					type: 'p',
					text: 'Para eliminar uma zona, toque no respetivo marcador e confirme, ou use **Limpar tudo** para remover todas as zonas de uma vez. Depois toque em **Guardar**; remover uma zona volta a mostrar essa área nas partilhas públicas.',
				},
			],
		},
		{
			heading: 'Escolher uma boa zona',
			blocks: [
				{
					type: 'list',
					items: [
						'Centre a zona perto da sua porta de casa, e não exatamente nela, para que a orla do círculo não aponte diretamente para a sua casa.',
						'Faça-a suficientemente grande para cobrir algumas ruas. Um círculo minúsculo pode ainda revelar onde vive.',
						'Adicione uma para qualquer sítio de onde parte com regularidade, como o trabalho ou a casa de um amigo.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'As zonas cortam apenas a linha no mapa. O título, a descrição e as fotografias de uma corrida são mostrados tal como os escreveu, por isso não inclua moradas neles.',
				},
			],
		},
	],
	sources: {
		title: 'd9e7d40ed8ec1d93',
		summary: '04c4913e2da59def',
		's0.heading': '27ee9eff5654fc40',
		's0.b0': '0786f273bb90019e',
		's0.b1.i0': 'd76fc2aebe831b0b',
		's0.b1.i1': 'f895445f10db7b57',
		's0.b1.i2': '591dec4de03df2a3',
		's0.b2': '9bfc49abe8494ae1',
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
