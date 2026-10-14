import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'follow-a-race-live',
	title: 'Acompanhar uma prova em direto',
	summary: 'Veja uma prova enquanto decorre na página da prova em direto: corredores num mapa, quem está no percurso e quem já terminou em cada percurso.',
	sections: [
		{
			heading: 'Abrir a página em direto',
			blocks: [
				{
					type: 'p',
					text: 'O organizador partilha um link para a página da prova em direto ou, se conseguir ver o evento, abra-o e escolha **Visão do espectador**. Não precisa de conta. Se o evento for **Apenas membros**, tem de ser membro do clube para o ver.',
				},
				{
					type: 'p',
					text: 'O topo da página mostra o estado da prova:',
				},
				{
					type: 'list',
					items: [
						'**Pré-prova**: o organizador ainda não preparou o cronómetro da prova.',
						'**Preparada**: o cronómetro está preparado e à espera da partida.',
						'**A decorrer**: a prova está em curso, com o tempo decorrido.',
						'**Concluído**: a prova terminou.',
						'**Cancelado**: o organizador cancelou a prova.',
					],
				},
			],
		},
		{
			heading: 'O mapa',
			blocks: [
				{
					type: 'p',
					text: 'A menos que já tenha permitido mapas nas definições de cookies, o mapa fica desligado até escolher **Carregar mapa**, porque carregá-lo envia o seu endereço IP ao nosso fornecedor de mosaicos de mapa. Depois de carregado, cada corredor é um ponto colorido com um pequeno rasto do seu trajeto recente. Os telemóveis e relógios dos corredores enviam uma posição mais ou menos a cada 10 segundos, e a página atualiza-se sozinha.',
				},
				{
					type: 'illustration',
					id: 'follow-a-race-live',
					alt: 'Um percurso num mapa com corredores ao longo dele, cada um um ponto colorido com um pequeno rasto do seu trajeto recente, e uma bandeira na meta.',
				},
			],
		},
		{
			heading: 'No percurso',
			blocks: [
				{
					type: 'p',
					text: 'O quadro **No percurso** lista todos os corredores que enviaram uma posição, do mais adiantado para o mais atrasado, com distância, ritmo e tempo decorrido, e há um quadro por percurso quando a prova tem mais do que um. Cada linha diz também há quanto tempo foi atualizada pela última vez.',
				},
				{
					type: 'p',
					text: 'Não existe uma indicação “em pausa” à parte. Um corredor que parou (para apertar um atacador, num abastecimento ou porque pausou a gravação) ou que perdeu o sinal simplesmente deixa de ser atualizado. Ao fim de cerca de 90 segundos sem atualização, a sua linha é marcada como **ATRASADO**. Isso não significa que algo esteja mal; muitas vezes é só falta de sinal.',
				},
			],
		},
		{
			heading: 'Quem já terminou',
			blocks: [
				{
					type: 'p',
					text: 'Quem termina aparece em **Concluído** à medida que os resultados chegam, com um quadro por percurso quando a prova tem mais do que um. Os corredores que não terminaram aparecem em **Não concluiu**. Um resultado que o organizador ainda não aprovou é marcado como **Pendente**.',
				},
				{
					type: 'p',
					text: 'O que significam os tempos e as marcas está explicado em [[guide:race-results-explained|Perceber os resultados das provas]].',
				},
			],
		},
		{
			heading: 'Privacidade',
			blocks: [
				{
					type: 'list',
					items: [
						'Os nomes reais dos corredores só são mostrados a pessoas ligadas a eles por um seguimento, em qualquer dos sentidos. Todas as outras pessoas veem um identificador anónimo, como Corredor #A1B2.',
						'Perto da zona de privacidade de um corredor, a sua posição exata fica oculta. Em vez disso, vê **Visto pela última vez perto daqui · aproximado**, mostrado como um anel vazio em vez de um ponto.',
						'Os corredores que o organizador importou de uma lista de dorsais não têm conta, por isso mantêm o nome que o organizador introduziu.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Qualquer pessoa com o link pode ver. Se vai correr a prova e prefere não ser acompanhado em direto, fale com o organizador antes da prova.',
				},
			],
		},
	],
	sources: {
		title: '2c62c5274378a304',
		summary: '6907f1876e7b883e',
		's0.heading': '9e53c8e8fdd29829',
		's0.b0': '386a683bed4bd1dd',
		's0.b1': 'c2d62153581d81fa',
		's0.b2.i0': '3a6d56e541fe4565',
		's0.b2.i1': 'c3dd12cae69c5cf5',
		's0.b2.i2': '120d1d8d969ced75',
		's0.b2.i3': 'fbe2e397efb8ef5e',
		's0.b2.i4': '1709d9ad712d85d2',
		's1.heading': 'dc711bb38f5066a7',
		's1.b0': 'f40d0503826f0955',
		's2.heading': '46db515d7f1689a7',
		's2.b0': '3316e288511685d1',
		's2.b1': 'cff7f7798a6785c9',
		's3.heading': '7804f7a79a9eee32',
		's3.b0': '4355700d3a60d89c',
		's3.b1': 'ea613ba62f6ba84a',
		's4.heading': '54a57c3147c49f33',
		's4.b0.i0': 'b8c1ad08a0dc3387',
		's4.b0.i1': '7cf40c647db03cc3',
		's4.b0.i2': 'edbbe7f08d1cf63e',
		's4.b1': '1bb7132a7305e850',
		's1.b1': '1afba2a8fcb03c42',
	},
};
