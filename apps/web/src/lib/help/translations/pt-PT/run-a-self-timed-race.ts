import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'run-a-self-timed-race',
	title: 'Correr uma prova de tempo próprio',
	summary: 'Inscreva-se numa prova aberta durante uma janela de tempo, marque a sua corrida como tentativa e corra da linha de partida à linha de chegada quando lhe der jeito.',
	sections: [
		{
			heading: 'O que é uma prova de tempo próprio',
			blocks: [
				{
					type: 'p',
					text: 'Uma prova de tempo próprio não tem partida em grupo. O organizador abre uma janela, que pode durar até uma semana, e enquanto ela estiver aberta pode correr o percurso quando quiser. O seu tempo conta desde que atravessa a linha de partida até atravessar a linha de chegada, por isso não há tempo oficial.',
				},
				{
					type: 'p',
					text: 'Grava a sua tentativa com a app do telemóvel ou com um relógio Wear OS. A web serve para se inscrever e ver resultados; um navegador não consegue gravar uma corrida.',
				},
			],
		},
		{
			heading: 'Antes de sair',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o evento da prova, na web ou na app do telemóvel.',
						'Se houver mais do que um percurso, escolha primeiro o seu.',
						'Escolha **Participar e tentar**. Se já disse **Eu vou**, já está inscrito.',
						'Abra a app uma vez enquanto tem sinal, antes de partir. Assim a app fica a conhecer a prova, e o aviso da prova e a sua tentativa continuam a funcionar onde não há sinal.',
					],
				},
			],
		},
		{
			heading: 'Iniciar a sua tentativa',
			blocks: [
				{
					type: 'steps',
					items: [
						'No separador Corrida da app do telemóvel, o aviso da prova mostra **Tempo próprio** e a hora a que a janela fecha.',
						'Toque em **Esta corrida é a minha tentativa**. Passa a **Tentativa pronta: toque em Iniciar**; toque de novo se mudar de ideias.',
						'Prima Iniciar antes de chegar à linha de partida e depois atravesse a linha de partida no sentido do percurso.',
					],
				},
				{
					type: 'p',
					text: 'Num relógio Wear OS, o ecrã antes de começar mostra TEMPO PRÓPRIO. Toque em **Esta corrida é a minha tentativa** e depois em Iniciar.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Uma corrida que não marque como tentativa nunca entra na prova: não envia posição em direto nem recebe resultado. Assim, uma corrida que não pretendia disputar nunca aparece no quadro.',
				},
			],
		},
		{
			heading: 'Tentativas e o seu resultado',
			blocks: [
				{
					type: 'list',
					items: [
						'Pode fazer mais do que uma tentativa enquanto a janela estiver aberta. Toque em **Esta corrida é a minha tentativa** antes de cada uma.',
						'Conta a sua melhor chegada cronometrada pelas duas linhas. Uma tentativa mais lenta não a substitui.',
						'O seu resultado pode ficar à espera da aprovação do organizador. Até lá, aparece como pendente e não tem posição.',
						'Um resultado sem passagem pela linha de partida, como um enviado de um Apple Watch ou de uma versão antiga da app, é guardado, mas o organizador revê-o antes de contar.',
					],
				},
				{
					type: 'p',
					text: 'O significado dos tempos no quadro é explicado em [[guide:race-results-explained|Perceber os resultados das provas]].',
				},
			],
		},
		{
			heading: 'Se o telemóvel falhou uma linha',
			blocks: [
				{
					type: 'p',
					text: 'O telemóvel ou o relógio diz “Linha de partida atravessada, a cronometrar” quando o vê atravessar a linha de partida, e regista a sua chegada na linha de chegada. Se falhar uma delas, por exemplo debaixo de árvores ou quando parte um pouco ao lado da linha:',
				},
				{
					type: 'list',
					items: [
						'Na chegada, toque em Parar e depois em **Terminar prova**. Se já tiver percorrido 90% do percurso, isso envia o seu tempo, e o organizador revê-o antes de ele contar.',
						'Ou volte a cronometrar a sua tentativa a partir do trajeto, mais tarde: abra a corrida na web e escolha **Cronometrar de novo pelo meu trajeto**. Isto cronometra o trajeto pelas linhas da prova e substitui um resultado à espera de revisão, ou um mais lento. Pode fazê-lo até 24 horas depois de a janela fechar.',
						'Correu com um Apple Watch? Não deteta as linhas, por isso voltar a cronometrar a partir do trajeto é a forma de a sua tentativa obter um resultado cronometrado pelas linhas.',
					],
				},
				{
					type: 'p',
					text: 'Mais sobre como voltar a cronometrar em [[guide:race-results-explained|Perceber os resultados das provas]].',
				},
			],
		},
	],
	sources: {
		title: '980e3fe539fa87ed',
		summary: '8200cb3990ca1c84',
		's0.heading': 'da16fddd6466ff82',
		's0.b0': 'b166c8e10ca64251',
		's0.b1': '9eb15ab29b32b50a',
		's1.heading': 'c682ac1a8b55d5bd',
		's1.b0.i0': 'f2699d62a364214c',
		's1.b0.i1': '15f502c0495a6810',
		's1.b0.i2': 'd67ce3877679d3b7',
		's1.b0.i3': 'd5058d744cf24c6b',
		's2.heading': '6e3e520b08e75a87',
		's2.b0.i0': '6b5b44bd7545a139',
		's2.b0.i1': '48bf3f903a530a73',
		's2.b0.i2': 'ff90c543a96100a6',
		's2.b1': '34ded6bec1fb4447',
		's2.b2': 'e9496d6a3325b124',
		's3.heading': '4ad1d4e8c17417b8',
		's3.b0.i0': 'a0858a05aad2d12a',
		's3.b0.i1': '82cda99fabf47908',
		's3.b0.i2': 'a6113125dae261a1',
		's3.b0.i3': '8e98409f10047bd7',
		's3.b1': '71fadd9d562da318',
		's4.heading': '9f401b8bc89ad9f0',
		's4.b0': 'c83ffd00a5d79eaf',
		's4.b1.i0': '371c0ea180b0a2cc',
		's4.b1.i1': 'd4b32e20b9afba25',
		's4.b1.i2': '30e86640bcd591b4',
		's4.b2': '172cd34b60d4d532',
	},
};
