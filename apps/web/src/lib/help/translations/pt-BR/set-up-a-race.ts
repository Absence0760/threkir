import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'set-up-a-race',
	title: 'Configurar uma prova',
	summary: 'Crie um evento do clube com um ou mais percursos para que os participantes escolham uma distância, sejam cronometrados ao vivo e apareçam em uma classificação por percurso.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'p',
					text: 'Uma prova é um evento comum do clube com percursos vinculados. Proprietários, administradores e organizadores de eventos do clube podem criar eventos. Conduzir a prova no dia (Preparar, JÁ, Finalizar) exige um proprietário, um administrador ou um **Diretor de prova** — veja [[guide:race-day-for-hosts|Dia de prova para organizadores]].',
				},
				{
					type: 'p',
					text: 'Os percursos são montados na web. O app para celular pode criar um evento simples, mas não tem editor de percursos, então adicione ou altere percursos pelo navegador.',
				},
			],
		},
		{
			heading: 'Criar o evento',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o seu clube e escolha **Novo evento**.',
						'Em **Tipo de evento**, escolha **Corrida em grupo** (ou **Ciclismo**). Eventos de aula e sociais não têm rota, distância, controles de prova nem resultados.',
						'Dê a ele um **Título** e uma **Data**. Defina uma repetição só se a prova realmente se repetir; cada ocorrência é disputada separadamente.',
						'Escolha uma **Rota** e preencha a **Distância**. Juntas, elas formam o seu *percurso principal*.',
						'Se quiser, digite um **Nome do percurso principal** em **Percursos da corrida** (por exemplo, “Meia maratona”). Se deixar em branco, o nome da rota é usado.',
						'Escolha **Criar evento**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'A linha de chegada em que os participantes são cronometrados é o último ponto da rota do percurso. Desenhe a rota para que ela termine exatamente onde vai ficar o seu pórtico de chegada.',
				},
			],
		},
		{
			heading: 'Adicionar mais percursos',
			blocks: [
				{
					type: 'p',
					text: 'Vai ter mais de uma distância no mesmo dia? Adicione cada distância extra como um percurso próprio. Cada percurso ganha a sua própria classificação.',
				},
				{
					type: 'steps',
					items: [
						'No editor do evento, encontre **Percursos da corrida** e escolha **Adicionar um percurso**.',
						'Dê a ele um **Nome do percurso**, escolha a **Rota** e informe a distância.',
						'Use as setas para cima e para baixo para reordenar os percursos, ou remova um de que você não precisa mais.',
						'Salve o evento.',
					],
				},
				{
					type: 'list',
					items: [
						'Todo percurso precisa de um nome, e dois percursos não podem ter o mesmo nome.',
						'Um percurso sem rota não tem ponto de chegada, então os participantes dele não têm a chegada registrada automaticamente; eles concluem manualmente pelo próprio dispositivo.',
						'Um percurso sem distância não consegue verificar se o participante cobriu a maior parte do percurso, então os participantes dele também concluem manualmente.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Vincular uma rota mostra o ponto de chegada dela a todos que podem ver o evento, mesmo que a própria rota seja privada. Você só pode vincular rotas que tem permissão para ver.',
				},
			],
		},
		{
			heading: 'O que os participantes veem',
			blocks: [
				{
					type: 'list',
					items: [
						'Na página do evento, os participantes veem os percursos. Quando há mais de um, eles precisam escolher um em **Seu percurso** antes que **Eu vou** funcione; caso contrário, veem “Escolha seu percurso primeiro.”',
						'No app para celular, tocar em **Eu vou** em uma prova com vários percursos abre **Escolha seu percurso**, e depois a pessoa pode usar **Trocar de percurso**.',
						'Com um único percurso, ninguém precisa escolher nada.',
						'As inscrições pagas ainda não pedem um percurso. Um participante pagante escolhe um depois, no mesmo menu **Seu percurso**.',
					],
				},
				{
					type: 'p',
					text: 'O lado do participante é explicado em [[guide:racing-in-a-race|Correr uma prova ao vivo]].',
				},
			],
		},
		{
			heading: 'Aprovar resultados automaticamente',
			blocks: [
				{
					type: 'p',
					text: 'Logo antes de preparar a prova, você escolhe se os resultados vão direto para a classificação. **Aprovar automaticamente os resultados enviados** vem marcado por padrão. Desmarque se quiser conferir cada resultado antes; cada um então aparece como **PENDENTE** até você aprová-lo.',
				},
			],
		},
		{
			heading: 'Compartilhar o link para espectadores',
			blocks: [
				{
					type: 'p',
					text: 'Cada ocorrência de prova tem uma página ao vivo com um mapa e quadros. Na página do evento, o cartão de controle da prova tem um link **Visão do espectador** que a abre em uma nova aba. Copie esse endereço e compartilhe com a família, os amigos e o canal da sua prova.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Em um evento **Somente para membros**, só os membros do clube podem ver o evento, então a página do espectador não vai funcionar para quem é de fora do clube.',
				},
				{
					type: 'p',
					text: 'O que os espectadores veem está explicado em [[guide:follow-a-race-live|Acompanhar uma prova ao vivo]].',
				},
			],
		},
	],
	sources: {
		title: '9c550364ef27a6b1',
		summary: '366fcefd4c4d302c',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': 'e59685e187f9a957',
		's0.b1': '6109c712395ba1b9',
		's1.heading': 'bdd2bbbddd9c3cf5',
		's1.b0.i0': 'ad4d295ffcc8f3a0',
		's1.b0.i1': '6f2498dc63953e9d',
		's1.b0.i2': '1de2284a85b9b8d0',
		's1.b0.i3': '66dae8991279459e',
		's1.b0.i4': '5dc3211a9d733e18',
		's1.b0.i5': '9b013cf91adfef1d',
		's1.b1': '4dedb854832fabbb',
		's2.heading': 'aa02687fee3b093f',
		's2.b0': '1e44be9c1cbe6aa5',
		's2.b1.i0': '59ec7388c26ff153',
		's2.b1.i1': '7e55782eb49cd9f2',
		's2.b1.i2': 'b71f0dd3bc7d65dd',
		's2.b1.i3': 'e70bf0579a469363',
		's2.b2.i0': 'd37d68f01d59d140',
		's2.b2.i1': '614d8a4a47ff46c0',
		's2.b2.i2': '6ba6f0661b9e166a',
		's2.b3': '47950903add3bde2',
		's3.heading': '8b4ed9e415e501f7',
		's3.b0.i0': '7366e2c6f9eafeb3',
		's3.b0.i1': '76dc29eb1e584662',
		's3.b0.i2': '295fb740c0b19c57',
		's3.b0.i3': 'f12d86e7aff3dc0e',
		's3.b1': 'd636d4186f153c0f',
		's4.heading': 'ff04ee128bd05b1f',
		's4.b0': '8887aff2546f155b',
		's5.heading': '05127d2bcbe7e55c',
		's5.b0': '632ca275dd6dbc2e',
		's5.b1': 'd81f08a86fd29b85',
		's5.b2': '7375e2668380d4e1',
	},
};
