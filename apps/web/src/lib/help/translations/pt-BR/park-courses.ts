import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'park-courses',
	title: "Percursos de parques: pontos de controle, temporadas e rankings",
	summary: "Como um percurso de parque cronometra a sua corrida, por que cada ponto de controle conta, quando uma temporada começa e como os rankings Mais rápidos e Mais conclusões classificam.",
	sections: [
		{
			heading: "O que é um percurso de parque",
			blocks: [
				{ type: 'p', text: "Um percurso de parque é um percurso fixo de contrarrelógio em uma trilha de um parque estadual ou nacional. Não há organizador nem dia de prova: corra quando o parque estiver aberto, e uma corrida que cobre o percurso inteiro é cronometrada. Encontre-os em **Corra quando quiser**, em [[route:/races|Provas e percursos]], com os mais próximos primeiro quando você define um local, ou veja todos em [[route:/parks|Percursos de parques]]." },
				{
					type: 'list',
					items: [
						"É um contrarrelógio, não uma corrida. A trilha continua aberta a todos e ninguém faz o controle, então siga as regras do parque e dê passagem às outras pessoas na trilha.",
						"Cada página de percurso mostra a distância, o ganho de elevação, o formato, o piso e a dificuldade, de onde veio a linha do percurso e se ele está aberto.",
						"Selecione **Navegar neste percurso** para seguir o percurso como uma rota. A opção não aparece enquanto o percurso estiver fechado.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Um percurso fechado mantém os tempos e rankings, mas não corra nele até que reabra. A página mostra quando o status foi verificado pela última vez." },
			],
		},
		{
			heading: "Pontos de controle: por que atalhos nunca contam",
			blocks: [
				{ type: 'p', text: "Além da largada e da chegada, um percurso pode ter pontos de controle pelo caminho. A sua corrida só é cronometrada se passar por todos os pontos de controle, na ordem, entre a largada e a chegada. Uma corrida que corta uma curva, pula um zigue-zague ou atravessa pelo meio perde um ponto de controle e não ganha tempo." },
				{ type: 'p', text: "Fique na trilha sinalizada. Cortar caminho danifica a trilha, e os parques tratam isso como uma infração das suas regras." },
			],
		},
		{
			heading: "As temporadas seguem o relógio do parque",
			blocks: [
				{ type: 'p', text: "Uma temporada é um ano civil no fuso horário do parque, não no seu. Os rankings recomeçam à meia-noite de 1º de janeiro onde o parque fica." },
				{ type: 'p', text: "Por exemplo, uma corrida que começa às 22:00 de 31 de dezembro em um parque da Virgínia conta para aquele ano, mesmo que o seu celular esteja em um fuso onde já é 1º de janeiro." },
			],
		},
		{
			heading: "O ranking Mais rápidos",
			blocks: [
				{
					type: 'list',
					items: [
						"**Mais rápidos** ordena cada corredor pelo seu melhor tempo no percurso. Você aparece uma vez, com a sua melhor corrida.",
						"Por padrão ele mostra este ano. Selecione **Todos os tempos** para ver os melhores tempos de todos os tempos.",
						"Filtre por gênero ou faixa etária. O filtro de idade só inclui quem concordou em compartilhar dados de saúde, então pode ser menor que o ranking completo.",
					],
				},
			],
		},
		{
			heading: "O ranking Mais conclusões",
			blocks: [
				{ type: 'p', text: "**Mais conclusões** premia quem volta sempre. Ele conta os dias em que você concluiu o percurso, no fuso horário do parque, então várias voltas no mesmo dia contam como uma." },
			],
		},
		{
			heading: "Quem aparece nos rankings",
			blocks: [
				{
					type: 'list',
					items: [
						"Você precisa estar conectado para ver os rankings. Sem entrar na conta, a página do percurso ainda mostra o percurso e um link **Entrar**.",
						"O tempo de uma corrida que outras pessoas não podem ver não é mostrado a elas.",
						"Você não vê as pessoas que bloqueou, e elas não veem você.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Uma corrida é comparada com os percursos de parque nos nossos servidores logo depois de ser salva ou importada, de qualquer dispositivo. Um novo tempo pode levar alguns minutos para aparecer em um ranking." },
			],
		},
	],
	sources: {
		title: "c0967d2bf224e3d2",
		summary: "6a173631b44944bc",
		"s0.heading": "216fc084817bfda9",
		"s0.b0": "a96a5717c602367f",
		"s0.b1.i0": "a8567bc2512800d1",
		"s0.b1.i1": "420575263613791d",
		"s0.b1.i2": "d69fbf280d3b46a0",
		"s0.b2": "6a9e63c1eec9c80f",
		"s1.heading": "0026d1ddae689c8a",
		"s1.b0": "f00cd3cca5bfc92f",
		"s1.b1": "36e6dc7fd586b7d7",
		"s2.heading": "5ba4de4e9cb351a4",
		"s2.b0": "f5cb979a283038fa",
		"s2.b1": "6afb246fc0e80841",
		"s3.heading": "f90c634a3c69c00f",
		"s3.b0.i0": "8bab47facf52e4fd",
		"s3.b0.i1": "c74b158f75754752",
		"s3.b0.i2": "a26ad1f8b547015d",
		"s4.heading": "d62c88ea85d104ce",
		"s4.b0": "23512913978ca5c1",
		"s5.heading": "b119ed9eec93efe3",
		"s5.b0.i0": "bee88a50dcbbbfa2",
		"s5.b0.i1": "25229437ce8179b8",
		"s5.b0.i2": "c95241619d2e3582",
		"s5.b1": "f0b47eeb5f542fe4",
	},
};
