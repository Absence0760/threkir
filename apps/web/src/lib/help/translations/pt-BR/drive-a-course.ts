import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'drive-a-course',
	title: "Percorrer de carro o percurso de uma prova antes do dia",
	summary: "Abra um percurso público no seu app de mapas, veja quais trechos ele não consegue seguir e deixe o app do celular ler em voz alta as notas do percurso enquanto você dirige.",
	sections: [
		{
			heading: "O que faz",
			blocks: [
				{ type: 'p', text: "Em uma rota pública ou em uma prova com percurso público, **Percorrer o percurso de carro** divide o percurso em trechos que o Google Maps, o Mapas da Apple ou o Waze conseguem seguir. O seu app de mapas faz a navegação, inclusive no CarPlay e no Android Auto." },
				{
					type: 'list',
					items: [
						"O Google Maps aceita várias paradas por trecho. O Mapas da Apple e o Waze aceitam um destino por vez, então você abre cada trecho em sequência.",
						"Percursos de prova usam trilhas, pontes e ruas fechadas. A lista abaixo dos trechos mostra os trechos que o app de mapas não consegue seguir, para você saber quais partes não vai ver.",
						"A rota do app de mapas serve só de orientação. As notas seguem o percurso real.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Este recurso está sendo liberado aos poucos. Se um percurso público não mostrar **Percorrer o percurso de carro**, ele ainda não está disponível para você." },
			],
		},
		{
			heading: "Abrir um percurso no app de mapas",
			blocks: [
				{
					type: 'steps',
					items: [
						"Abra a rota ou a prova e selecione **Percorrer o percurso de carro**.",
						"Escolha o seu app de mapas e selecione **Ir até a largada**.",
						"Na largada, abra o trecho 1. Quando um trecho terminar, abra o próximo.",
					],
				},
				{ type: 'p', text: "A página web também lista cada nota do percurso com a distância, e você pode imprimir a lista para um passageiro." },
			],
		},
		{
			heading: "Ouvir as notas do percurso no celular",
			blocks: [
				{
					type: 'steps',
					items: [
						"No app do celular, abra a rota ou a prova e toque em **Percorrer o percurso de carro**.",
						"Leia o aviso de segurança e toque em **Entendi**. Ele aparece só uma vez em cada celular.",
						"Toque em **Iniciar notas faladas**, mude para o seu app de mapas e bloqueie o celular.",
					],
				},
				{ type: 'p', text: "Cada posto de hidratação, tempo limite, subida, perigo e nota é lido cerca de 15 segundos antes de você chegar e de novo quando você está lá. Se você entrar no meio, as notas começam de onde você está. Elas param na chegada ou depois de 10 minutos fora do percurso. Toque em **Parar** para encerrá-las antes." },
				{ type: 'note', tone: 'caution', text: "Use com um passageiro ou com o celular em um suporte e não toque no celular enquanto dirige. Siga as regras e a sinalização de trânsito e lembre-se de que as ruas do percurso podem estar fechadas no dia da prova." },
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
