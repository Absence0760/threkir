import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'run-a-self-timed-race',
	title: 'Correr uma prova de tempo próprio',
	summary: 'Participe de uma prova aberta durante uma janela de tempo, marque sua corrida como sua tentativa e corra da linha de largada até a linha de chegada quando for melhor para você.',
	sections: [
		{
			heading: 'O que é uma prova de tempo próprio',
			blocks: [
				{
					type: 'p',
					text: 'Uma prova de tempo próprio não tem largada em grupo. O organizador abre uma janela, que pode durar até uma semana, e você corre o percurso quando quiser enquanto ela estiver aberta. Seu tempo vai de quando você cruza a linha de largada até quando cruza a linha de chegada, então não há tempo bruto.',
				},
				{
					type: 'p',
					text: 'Você grava sua tentativa com o app do celular ou com um relógio Wear OS. A web serve para participar e ver os resultados; um navegador não consegue gravar uma corrida.',
				},
			],
		},
		{
			heading: 'Antes de sair',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o evento da prova, na web ou no app do celular.',
						'Se houver mais de um percurso, escolha o seu primeiro.',
						'Escolha **Participar e tentar**. Se você já disse **Eu vou**, já está participando.',
						'Abra o app uma vez enquanto tiver sinal, antes de sair. Assim ele fica sabendo da prova, e o banner da prova e a sua tentativa continuam funcionando onde não há sinal.',
					],
				},
			],
		},
		{
			heading: 'Começar sua tentativa',
			blocks: [
				{
					type: 'steps',
					items: [
						'Na aba Corrida do app do celular, o banner da prova mostra **Tempo próprio** e quando a janela fecha.',
						'Toque em **Esta corrida é a minha tentativa**. O botão muda para **Tentativa pronta: toque em Iniciar**; toque de novo se mudar de ideia.',
						'Pressione Iniciar antes de chegar à linha de largada e depois passe pela linha de largada no sentido do percurso.',
					],
				},
				{
					type: 'p',
					text: 'Em um relógio Wear OS, a tela antes de você iniciar mostra TEMPO PRÓPRIO. Toque em **Esta corrida é a minha tentativa** e depois em Iniciar.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Uma corrida que você não marca como sua tentativa nunca entra na prova: ela não envia posição ao vivo e não recebe resultado. Assim, uma corrida que você não pretendia disputar nunca vai parar na classificação.',
				},
			],
		},
		{
			heading: 'Tentativas e seu resultado',
			blocks: [
				{
					type: 'list',
					items: [
						'Você pode fazer mais de uma tentativa enquanto a janela estiver aberta. Toque em **Esta corrida é a minha tentativa** antes de cada uma.',
						'Vale a sua melhor chegada cronometrada pelas duas linhas. Uma tentativa mais lenta não a substitui.',
						'Seu resultado pode aguardar a aprovação do organizador. Até lá, ele aparece como pendente e não tem colocação.',
						'Um resultado sem cruzamento da linha de largada, como um enviado de um Apple Watch ou de uma versão antiga do app, fica guardado, mas o organizador o revisa antes que ele conte.',
					],
				},
				{
					type: 'p',
					text: 'O que significam os tempos na classificação está em [[guide:race-results-explained|Como funcionam os resultados de prova]].',
				},
			],
		},
		{
			heading: 'Se o seu celular não detectou uma linha',
			blocks: [
				{
					type: 'p',
					text: 'Seu celular ou relógio diz “Linha de largada cruzada, cronometrando” quando detecta que você cruzou a linha de largada, e registra sua chegada na linha de chegada. Se ele não detectar uma delas, por exemplo sob árvores ou quando você larga um pouco ao lado da linha:',
				},
				{
					type: 'list',
					items: [
						'Na chegada, toque em Parar e depois em **Finalizar prova**. Se você já cobriu 90% do percurso, isso envia seu tempo, e o organizador o revisa antes que ele conte.',
						'Ou, depois, recronometre sua tentativa pelo trajeto dela: abra a corrida na web e escolha **Recronometrar pelo meu trajeto**. Isso cronometra o trajeto pelas linhas da prova e substitui um resultado aguardando revisão ou um mais lento. Você pode fazer isso até 24 horas depois que a janela fechar.',
						'Correu com um Apple Watch? Ele não detecta as linhas, então recronometrar pelo seu trajeto é a forma de a sua tentativa receber um resultado cronometrado pelas linhas.',
					],
				},
				{
					type: 'p',
					text: 'Mais sobre recronometragem em [[guide:race-results-explained|Como funcionam os resultados de prova]].',
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
