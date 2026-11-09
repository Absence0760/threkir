import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'drive-a-course',
	title: "Percorrer o percurso de uma prova de carro antes do dia",
	summary: "Abra um percurso público na sua app de mapas, veja que troços ela não consegue seguir e deixe a app do telemóvel ler em voz alta as notas do percurso enquanto conduz.",
	sections: [
		{
			heading: "O que faz",
			blocks: [
				{ type: 'p', text: "Numa rota pública ou numa prova com percurso público, **Percorrer o percurso de carro** divide o percurso em troços que o Google Maps, os Mapas da Apple ou o Waze conseguem seguir. A sua app de mapas faz a navegação, incluindo no CarPlay e no Android Auto." },
				{
					type: 'list',
					items: [
						"O Google Maps aceita várias paragens por troço. Os Mapas da Apple e o Waze aceitam um destino de cada vez, por isso abre cada troço à vez.",
						"Os percursos de prova usam caminhos, pontes e estradas fechadas. A lista por baixo dos troços mostra os troços que a app de mapas não consegue seguir, para saber que partes não vai ver.",
						"A rota da app de mapas serve apenas de orientação. As notas seguem o percurso real.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Esta funcionalidade está a ser ativada aos poucos. Se um percurso público não mostrar **Percorrer o percurso de carro**, ainda não está disponível para si." },
			],
		},
		{
			heading: "Abrir um percurso na app de mapas",
			blocks: [
				{
					type: 'steps',
					items: [
						"Abra a rota ou a prova e selecione **Percorrer o percurso de carro**.",
						"Escolha a sua app de mapas e selecione **Ir para a partida**.",
						"Na partida, abra o troço 1. Quando um troço terminar, abra o seguinte.",
					],
				},
				{ type: 'p', text: "A página web também lista cada nota do percurso com a sua distância, e pode imprimir a lista para um passageiro." },
			],
		},
		{
			heading: "Ouvir as notas do percurso no telemóvel",
			blocks: [
				{
					type: 'steps',
					items: [
						"Na app do telemóvel, abra a rota ou a prova e toque em **Percorrer o percurso de carro**.",
						"Leia o aviso de segurança e toque em **Compreendo**. Só aparece uma vez em cada telemóvel.",
						"Toque em **Iniciar notas faladas**, mude para a sua app de mapas e bloqueie o telemóvel.",
					],
				},
				{ type: 'p', text: "Cada abastecimento, tempo limite, subida, perigo e nota é lido cerca de 15 segundos antes de lá chegar e outra vez quando lá está. Se se juntar a meio, as notas começam onde está. Param na meta ou após 10 minutos fora do percurso. Toque em **Parar** para as terminar mais cedo." },
				{ type: 'note', tone: 'caution', text: "Use-a com um passageiro ou com o telemóvel num suporte e não toque no telemóvel enquanto conduz. Cumpra as regras e a sinalização de trânsito, e lembre-se de que as estradas do percurso podem estar fechadas no dia da prova." },
			],
		},
	],
	sources: {
		"title": "bbb89d013c30ae16",
		"summary": "48a420988cbd14e8",
		"s0.heading": "c74ea9dc9cd25b58",
		"s0.b0": "0c0cd5387f11ea68",
		"s0.b1.i0": "f99832ea6336c2e7",
		"s0.b1.i1": "f1890d3bd7eb5850",
		"s0.b1.i2": "2a2afee7d8920207",
		"s0.b2": "7d8297dee5795cc5",
		"s1.heading": "bcc63fa1329139a9",
		"s1.b0.i0": "14946890d3f8e349",
		"s1.b0.i1": "d191e63d2defd3a9",
		"s1.b0.i2": "886b24e27ccf472f",
		"s1.b1": "96f5e8e63b56c989",
		"s2.heading": "5d546a4fc1ae50a1",
		"s2.b0.i0": "c555d1adaded1b5f",
		"s2.b0.i1": "72929bf136e6a2eb",
		"s2.b0.i2": "888f501170932dde",
		"s2.b1": "d5bf7e3b65385652",
		"s2.b2": "86d1be053314ad10"
	},
};
