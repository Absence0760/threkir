import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'follow-a-race-live',
	title: 'Acompanhar uma prova ao vivo',
	summary: 'Assista a uma prova enquanto ela acontece na página da prova ao vivo: corredores em um mapa, quem está no percurso e quem já concluiu cada percurso.',
	sections: [
		{
			heading: 'Abrir a página ao vivo',
			blocks: [
				{
					type: 'p',
					text: 'O organizador compartilha um link para a página da prova ao vivo ou, se você consegue ver o evento, abra-o e escolha **Visão do espectador**. Você não precisa de uma conta. Se o evento for **Somente membros**, você precisa ser membro do clube para vê-lo.',
				},
				{
					type: 'p',
					text: 'O topo da página mostra o estado da prova:',
				},
				{
					type: 'list',
					items: [
						'**Pré-corrida**: o organizador ainda não preparou o cronômetro da prova.',
						'**Preparada**: o cronômetro está preparado e aguardando a largada.',
						'**Em andamento**: a prova começou, com o tempo decorrido.',
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
					text: 'A menos que você já tenha permitido mapas nas suas configurações de cookies, o mapa fica desligado até você escolher **Carregar mapa**, porque carregá-lo envia o seu endereço IP ao nosso provedor de tiles de mapa. Depois de carregado, cada corredor é um ponto colorido com um pequeno rastro do caminho recente. Os celulares e relógios dos corredores enviam uma posição mais ou menos a cada 10 segundos, e a página se atualiza sozinha.',
				},
				{
					type: 'illustration',
					id: 'follow-a-race-live',
					alt: 'Um percurso em um mapa com corredores ao longo dele, cada um um ponto colorido com um pequeno rastro do trajeto recente, e uma bandeira na chegada.',
				},
			],
		},
		{
			heading: 'No percurso',
			blocks: [
				{
					type: 'p',
					text: 'O quadro **No percurso** lista todos os corredores que enviaram uma posição, do mais adiantado para o menos, com distância, ritmo e tempo decorrido, com um quadro por percurso quando a prova tem mais de um. Cada linha também diz há quanto tempo foi atualizada pela última vez.',
				},
				{
					type: 'p',
					text: 'Não existe um rótulo separado de “pausado”. Um corredor que parou (para amarrar o tênis, em um posto de apoio ou porque pausou a gravação) ou que perdeu o sinal simplesmente para de atualizar. Depois de cerca de 90 segundos sem atualização, a linha dele é marcada como **ATRASADO**. Isso não significa que algo está errado; muitas vezes significa apenas falta de sinal.',
				},
			],
		},
		{
			heading: 'Concluídos',
			blocks: [
				{
					type: 'p',
					text: 'Quem termina aparece em **Concluído** conforme os resultados chegam, com um quadro por percurso quando a prova tem mais de um. Os corredores que não terminaram aparecem em **Não concluiu**. Um resultado que o organizador ainda não aprovou é marcado como **Pendente**.',
				},
				{
					type: 'p',
					text: 'O que os tempos e os selos significam está em [[guide:race-results-explained|Como funcionam os resultados de prova]].',
				},
			],
		},
		{
			heading: 'Privacidade',
			blocks: [
				{
					type: 'list',
					items: [
						'O nome verdadeiro de um corredor só é mostrado para quem segue esse corredor ou é seguido por ele. Todos os demais veem um apelido anônimo, como Corredor #A1B2.',
						'Perto da zona de privacidade de um corredor, a posição exata dele fica oculta. Em vez disso, você vê **Visto pela última vez perto daqui · aproximado**, mostrado como um anel vazado em vez de um ponto.',
						'Os concluintes importados pelo organizador de uma lista de números de peito não têm conta, então mantêm o nome que o organizador digitou.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Qualquer pessoa com o link pode assistir. Se você vai correr a prova e prefere não ser acompanhado ao vivo, fale com o organizador antes da prova.',
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
