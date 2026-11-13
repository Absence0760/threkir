import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'park-courses',
	title: "Percursos de parques: pontos de controlo, épocas e classificações",
	summary: "Como um percurso de parque cronometra a sua corrida, porque conta cada ponto de controlo, quando começa uma época e como ordenam as classificações Mais rápidos e Mais conclusões.",
	sections: [
		{
			heading: "O que é um percurso de parque",
			blocks: [
				{ type: 'p', text: "Um percurso de parque é um percurso fixo de contrarrelógio num trilho de um parque estadual ou nacional. Não há organizador nem dia de prova: corra-o quando o parque estiver aberto, e uma corrida que cubra o percurso completo é cronometrada nele. Encontre-os em **Corra quando quiser**, em [[route:/races|Provas e percursos]], com os mais próximos primeiro quando define um local, ou veja todos em [[route:/parks|Percursos de parques]]. Selecione **Percursos** no topo de Provas e percursos para listar todos os percursos à parte, sem o calendário de provas." },
				{
					type: 'list',
					items: [
						"É um contrarrelógio, não uma prova. O trilho continua aberto a todos e ninguém o controla, por isso cumpra as regras do parque e dê passagem às outras pessoas no trilho.",
						"Cada página de percurso mostra a distância, o desnível positivo, o formato, o piso e a dificuldade, de onde vem a linha do percurso e se está aberto.",
						"Selecione **Navegar neste percurso** para seguir o percurso como uma rota. A opção não aparece enquanto o percurso estiver fechado.",
						"O **Guia do percurso** na página do percurso indica onde estacionar e cada mudança de direção pela ordem, com o nome do trilho, além das pontes, vaus, mudanças de piso e subidas. É elaborado a partir de dados do mapa; enquanto ninguém o tiver verificado no parque, isso aparece acima da lista. O mesmo guia vem no ficheiro GPX do percurso.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Um percurso fechado não aceita tempos novos: uma corrida nele enquanto está fechado não é cronometrada, e os tempos que já tem mantêm-se nas classificações. Não o corra até reabrir. A página mostra quando o estado foi verificado pela última vez." },
			],
		},
		{
			heading: "Pontos de controlo: porque é que os atalhos nunca contam",
			blocks: [
				{ type: 'p', text: "Além da partida e da chegada, um percurso pode ter pontos de controlo pelo caminho. A sua corrida só é cronometrada se passar por todos os pontos de controlo, pela ordem, entre a partida e a chegada. Uma corrida que corta uma curva, salta um ziguezague ou atravessa pelo meio falha um ponto de controlo e não obtém tempo." },
				{ type: 'p', text: "Mantenha-se no trilho marcado. Cortar caminho danifica o trilho, e os parques consideram-no uma infração às suas regras." },
			],
		},
		{
			heading: "As épocas seguem o relógio do parque",
			blocks: [
				{ type: 'p', text: "Uma época é um ano civil no fuso horário do parque, não no seu. As classificações recomeçam à meia-noite de 1 de janeiro onde o parque fica." },
				{ type: 'p', text: "Por exemplo, uma corrida que começa às 22:00 de 31 de dezembro num parque da Virgínia conta para esse ano, mesmo que o seu telemóvel esteja num fuso horário em que já é 1 de janeiro." },
			],
		},
		{
			heading: "A classificação Mais rápidos",
			blocks: [
				{
					type: 'list',
					items: [
						"**Mais rápidos** ordena cada corredor pelo seu melhor tempo no percurso. Aparece uma vez, com a sua melhor corrida.",
						"Por predefinição mostra este ano. Selecione **Desde sempre** para ver os melhores tempos de sempre.",
						"Filtre por género ou escalão etário. O filtro de idade só inclui quem aceitou partilhar dados de saúde, por isso pode ser mais curto do que a classificação completa.",
					],
				},
			],
		},
		{
			heading: "A classificação Mais conclusões",
			blocks: [
				{ type: 'p', text: "**Mais conclusões** premeia os habituais. Conta os dias em que concluiu o percurso, no fuso horário do parque, por isso várias voltas no mesmo dia contam como uma." },
			],
		},
		{
			heading: "Quem aparece nas classificações",
			blocks: [
				{
					type: 'list',
					items: [
						"Tem de ter sessão iniciada para ver as classificações. Sem sessão iniciada, a página do percurso continua a mostrar o percurso e uma ligação **Iniciar sessão**.",
						"O tempo de uma corrida que os outros não podem ver não lhes é mostrado.",
						"Não vê as pessoas que bloqueou, e elas não o veem a si.",
					],
				},
				{ type: 'note', tone: 'caution', text: "Uma corrida é comparada com os percursos de parque nos nossos servidores pouco depois de ser guardada ou importada, a partir de qualquer dispositivo. Um novo tempo pode demorar alguns minutos a aparecer numa classificação." },
			],
		},
	],
	sources: {
		title: "c0967d2bf224e3d2",
		summary: "6a173631b44944bc",
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
