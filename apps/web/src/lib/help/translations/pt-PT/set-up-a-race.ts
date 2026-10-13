import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'set-up-a-race',
	title: 'Configurar uma prova',
	summary: 'Crie um evento de clube com um ou mais percursos para que os corredores possam escolher uma distância, ser cronometrados em direto e entrar numa classificação por percurso.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'p',
					text: 'Uma prova é um evento de clube normal com percursos associados. Os proprietários e administradores do clube e os organizadores de eventos podem criar eventos. Gerir a prova no dia (preparar, dar a partida, terminar) exige um proprietário, um administrador ou um **Diretor de prova** — consulte [[guide:race-day-for-hosts|Dia de prova para organizadores]].',
				},
				{
					type: 'p',
					text: 'Os percursos são criados na web. A app do telemóvel consegue criar um evento simples, mas não tem editor de percursos, por isso adicione ou altere percursos a partir de um navegador.',
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
						'Em **Tipo de evento**, escolha **Corrida em grupo** (ou **Ciclismo**). Os eventos de aula e os sociais não têm rota, distância, controlos de prova nem resultados.',
						'Dê-lhe um **Título** e uma **Data**. Defina uma repetição apenas se a prova se repetir mesmo; cada ocorrência é disputada separadamente.',
						'Escolha uma **Rota** e preencha a **Distância**. Juntas, formam o seu *percurso principal*.',
						'Opcionalmente, escreva um **Nome do percurso principal** em **Percursos da corrida** (por exemplo, “Meia maratona”). Se o deixar em branco, é usado o nome da rota.',
						'Escolha **Criar evento**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'A linha de meta em que os corredores são cronometrados é o último ponto da rota do percurso. Desenhe a rota de modo a que termine exatamente onde vai ficar o seu pórtico de meta.',
				},
			],
		},
		{
			heading: 'Adicionar mais percursos',
			blocks: [
				{
					type: 'p',
					text: 'Vai haver mais do que uma distância no mesmo dia? Adicione cada distância extra como um percurso próprio. Cada percurso tem a sua própria classificação.',
				},
				{
					type: 'steps',
					items: [
						'No editor do evento, encontre **Percursos da corrida** e escolha **Adicionar um percurso**.',
						'Dê-lhe um **Nome do percurso**, escolha a respetiva **Rota** e introduza a sua distância.',
						'Use as setas para cima e para baixo para reordenar os percursos, ou remova um de que já não precise.',
						'Guarde o evento.',
					],
				},
				{
					type: 'list',
					items: [
						'Cada percurso precisa de um nome, e dois percursos não podem ter o mesmo.',
						'Um percurso sem rota não tem ponto de chegada, por isso a chegada dos seus corredores não é registada automaticamente; terminam à mão a partir do dispositivo.',
						'Um percurso sem distância não consegue verificar se um corredor percorreu a maior parte do percurso, por isso os seus corredores também terminam à mão.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Associar uma rota mostra o respetivo ponto de chegada a todos os que podem ver o evento, mesmo que a rota em si seja privada. Só pode associar rotas que tem permissão para ver.',
				},
			],
		},
		{
			heading: 'O que os corredores veem',
			blocks: [
				{
					type: 'list',
					items: [
						'Na página do evento, os corredores veem os percursos. Quando há mais do que um, têm de escolher um em **O seu percurso** antes de **Eu vou** funcionar; caso contrário, veem “Escolha primeiro o seu percurso.”',
						'Na app do telemóvel, tocar em **Eu vou** numa prova com vários percursos mostra **Escolha o seu percurso**, e mais tarde podem usar **Mudar de percurso**.',
						'Com um único percurso, ninguém tem de escolher nada.',
						'As inscrições pagas ainda não pedem um percurso. Um corredor que pagou escolhe-o depois no mesmo menu **O seu percurso**.',
					],
				},
				{
					type: 'p',
					text: 'O lado de quem corre é explicado em [[guide:racing-in-a-race|Correr numa prova em direto]].',
				},
			],
		},
		{
			heading: 'Aprovar resultados automaticamente',
			blocks: [
				{
					type: 'p',
					text: 'Mesmo antes de preparar a prova, escolhe se os resultados vão diretamente para a classificação. **Aprovar automaticamente os resultados enviados** vem assinalado por predefinição. Desmarque-o se quiser verificar cada resultado primeiro; cada um aparece então como **PENDENTE** até o aprovar.',
				},
			],
		},
		{
			heading: 'Partilhar o link para espectadores',
			blocks: [
				{
					type: 'p',
					text: 'Cada ocorrência de uma prova tem uma página em direto com um mapa e quadros. Na página do evento, o cartão de controlo da prova tem um link **Visão do espectador** que a abre num novo separador. Copie esse endereço e partilhe-o com a família, os amigos e o canal da sua prova.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Num evento **Apenas para membros**, só os membros do clube podem ver o evento, por isso a página do espectador não funciona para pessoas de fora do clube.',
				},
				{
					type: 'p',
					text: 'O que os espectadores veem é explicado em [[guide:follow-a-race-live|Acompanhar uma prova em direto]].',
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
		's3.b1': 'b238271b4620d5dc',
		's4.heading': 'ff04ee128bd05b1f',
		's4.b0': '8887aff2546f155b',
		's5.heading': '05127d2bcbe7e55c',
		's5.b0': '632ca275dd6dbc2e',
		's5.b1': 'd81f08a86fd29b85',
		's5.b2': '7375e2668380d4e1',
	},
};
