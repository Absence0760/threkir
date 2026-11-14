import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'park-courses',
	title: "Percursos de parques: pontos de controle, temporadas, meses e classificações",
	summary: "Como um percurso de parque cronometra sua corrida, por que cada ponto de controle conta, quando começam a temporada e o mês e como as classificações Mais rápidos e Mais conclusões ordenam corredores.",
	sections: [
		{
			heading: "O que é um percurso de parque",
			blocks: [
				{ type: 'p', text: "Um percurso de parque é um percurso fixo de contrarrelógio em uma trilha de um parque estadual ou nacional. Não há organizador nem dia de prova: corra sempre que o parque estiver aberto, e uma corrida que cobre o percurso inteiro é cronometrada. Encontre-os em **Corra quando quiser**, em [[route:/races|Provas e percursos]], com os mais próximos primeiro quando você define um lugar, ou veja todos em [[route:/parks|Percursos de parques]]. Selecione **Percursos** no topo de Provas e percursos para listar só os percursos, um a um, sem o calendário de provas." },
				{
					type: 'list',
					items: [
						"É um contrarrelógio, não uma corrida. A trilha continua aberta a todos e ninguém faz o controle, então siga as regras do parque e dê passagem às outras pessoas na trilha.",
						"Cada página de percurso mostra a distância, o ganho de elevação, o formato, o piso e a dificuldade, de onde veio a linha do percurso e se ele está aberto.",
						"Selecione **Navegar neste percurso** para seguir o percurso como uma rota. A opção não aparece enquanto o percurso estiver fechado.",
						"O **Guia do percurso** na página do percurso mostra onde estacionar e cada conversão na ordem, com o nome da trilha, além das pontes, vaus, mudanças de piso e subidas. Ele é feito a partir de dados do mapa; enquanto ninguém o conferir no parque, isso aparece acima da lista. O mesmo guia vai no arquivo GPX do percurso.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Um percurso fechado não recebe tempos novos: uma corrida nele enquanto está fechado não é cronometrada, e os tempos que ele já tem continuam nas classificações. Não corra nele até que reabra. A página mostra quando o status foi verificado pela última vez." },
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
				{ type: 'p', text: "Uma temporada é um ano civil no fuso horário do parque, não no seu. As classificações recomeçam à meia-noite de 1º de janeiro onde o parque fica." },
				{ type: 'p', text: "Por exemplo, uma corrida que começa às 22:00 de 31 de dezembro em um parque da Virgínia conta para aquele ano, mesmo que o seu celular esteja em um fuso onde já é 1º de janeiro." },
			],
		},
		{
			heading: "A classificação Mais rápidos",
			blocks: [
				{
					type: 'list',
					items: [
						"**Mais rápidos** ordena cada corredor pelo seu melhor tempo no percurso. Você aparece uma vez, com a sua melhor corrida.",
						"Por padrão ela mostra este ano. Selecione **Este mês** para ver o mês até agora, ou **Todos os tempos** para ver os melhores tempos de todos os tempos.",
						"Filtre por gênero ou faixa etária. O filtro de idade só inclui quem deu consentimento de dados de saúde, então pode ser menor que a classificação completa.",
					],
				},
			],
		},
		{
			heading: "A classificação Mais conclusões",
			blocks: [
				{ type: 'p', text: "**Mais conclusões** premia quem volta sempre. Ela conta os dias em que você concluiu o percurso, no fuso horário do parque, então várias voltas no mesmo dia contam como uma." },
			],
		},
		{
			heading: "Meses: uma classificação nova todo mês",
			blocks: [
				{ type: 'p', text: "As duas classificações também funcionam mês a mês. Um mês é um mês do calendário no fuso horário do parque, da meia-noite do dia 1 à meia-noite do dia 1 do mês seguinte, então uma corrida às 23:30 de 31 de outubro no horário do parque conta para outubro." },
				{
					type: 'list',
					items: [
						"Selecione **Este mês** para ver o mês até agora, e use as setas ao lado do nome do mês para voltar a meses anteriores.",
						"Cada percurso na página de um parque mostra quantas pessoas o correram este mês.",
						"Um tempo em um percurso de parque, na página da sua corrida, mostra a posição naquele mês e naquele ano, por exemplo N.º 2 em novembro, n.º 9 em 2026. O adesivo **Percurso de parque** de uma imagem compartilhada mostra a posição do mês, e também a do ano quando ela está entre as 10 primeiras.",
						"Quando um mês termina no horário do parque, você recebe na caixa de entrada um aviso com seu melhor tempo daquele mês em cada percurso que correu. Desative com **Meses nos percursos de parque**: na web, em [[route:/settings/notifications|Notificações]]; no app do celular, em **Notificações** na aba **Você**.",
						"As medalhas de meses de parque contam os meses em que você concluiu um percurso de parque, aos 3, 6, 12 e 24 meses. Contam conclusões, nunca posições.",
					],
				},
			],
		},
		{
			heading: "Quem aparece nas classificações",
			blocks: [
				{
					type: 'list',
					items: [
						"Você precisa estar conectado para ver as classificações. Sem entrar na conta, a página do percurso ainda mostra o percurso e um link **Entrar**.",
						"O tempo de uma corrida que outras pessoas não podem ver não é mostrado a elas.",
						"Você não vê as pessoas que bloqueou, e elas não veem você.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Uma corrida é comparada com os percursos de parque nos nossos servidores logo depois de ser salva ou importada, de qualquer dispositivo. Um novo tempo pode levar alguns minutos para aparecer em uma classificação." },
			],
		},
	],
	sources: {
		title: "80ff9e4c22672c3e",
		summary: "a8d0d3cdf47ef5c6",
		"s0.heading": "216fc084817bfda9",
		"s0.b0": "c202f382c7f5c297",
		"s0.b1.i0": "a8567bc2512800d1",
		"s0.b1.i1": "420575263613791d",
		"s0.b1.i2": "d69fbf280d3b46a0",
		"s0.b1.i3": "a75477f7d5a5a5bc",
		"s0.b2": "a9aa6fec9968fc90",
		"s1.heading": "0026d1ddae689c8a",
		"s1.b0": "f00cd3cca5bfc92f",
		"s1.b1": "36e6dc7fd586b7d7",
		"s2.heading": "5ba4de4e9cb351a4",
		"s2.b0": "f5cb979a283038fa",
		"s2.b1": "6afb246fc0e80841",
		"s3.heading": "f90c634a3c69c00f",
		"s3.b0.i0": "8bab47facf52e4fd",
		"s3.b0.i1": "01322b98d3fa4762",
		"s3.b0.i2": "1b3d5a9034e460c5",
		"s4.heading": "d62c88ea85d104ce",
		"s4.b0": "23512913978ca5c1",
		"s5.heading": "2158104d68549d3e",
		"s5.b0": "f8cebd1b6b6f6d5c",
		"s5.b1.i0": "95832d49c27d961e",
		"s5.b1.i1": "e5fd55e453a25d9a",
		"s5.b1.i2": "0220ee50a2c3ffc2",
		"s5.b1.i3": "3c988cac91d6d886",
		"s5.b1.i4": "9f0fedf00dcae221",
		"s6.heading": "b119ed9eec93efe3",
		"s6.b0.i0": "bee88a50dcbbbfa2",
		"s6.b0.i1": "25229437ce8179b8",
		"s6.b0.i2": "c95241619d2e3582",
		"s6.b1": "f0b47eeb5f542fe4",
	},
};
