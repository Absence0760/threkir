import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'build-a-session-plan',
	title: 'Montar um plano de sessão de ioga, pilates ou mobilidade',
	summary: 'Escreva uma sequência cronometrada de posturas sustentadas, flows e repetições, com movimentos por lado e indicações, e depois dê aula com ela, vincule-a a uma aula e acompanhe-a.',
	sections: [
		{
			heading: 'Onde montar',
			blocks: [
				{
					type: 'p',
					text: 'Os planos de sessão são escritos na web. O app do celular lista e executa os planos, mas ainda não tem editor.',
				},
				{
					type: 'list',
					items: [
						'Para você: abra [[route:/plans/new|Novo plano]] e escolha **Plano de sessão**, ou clique em **Nova sessão** em [[route:/sessions|Sessões]].',
						'Para o seu clube: na aba **Modelos** do clube, clique em **Adicionar modelo** e escolha **Plano de sessão**. Ele é salvo como modelo do clube na hora.',
					],
				},
			],
		},
		{
			heading: 'Preencher o plano',
			blocks: [
				{
					type: 'steps',
					items: [
						'Dê a ele um **Título** que nomeie a sequência, como “Flow de abertura de quadril, 45 min”.',
						'Adicione uma **Modalidade** (por exemplo, ioga vinyasa) e o **Equipamento** que as pessoas devem ter à mão, como um tapete ou um reformer.',
						'Se quiser, clique em **Adicionar bloco** para dividi-lo em seções como Aquecimento, Em pé e Desaquecimento. Um plano sem blocos é executado de uma vez, do início ao fim.',
						'Clique em **Adicionar movimento** para cada postura ou exercício e digite o nome em **Movimento**.',
						'Escolha o **Tipo**: **Sustentar** para uma postura cronometrada, **Flow** para uma sequência de movimentos cronometrada, ou **Reps.** para um exercício contado. Depois, informe os **Segundos** ou as **Repetições** e o **Bloco** a que ele pertence.',
						'Marque **Por lado (esquerdo e direito)** para o que for feito de cada lado. Ele é executado uma vez para cada lado, então leva o dobro do tempo.',
						'Se quiser, adicione um **Tempo** e uma **Indicação**, a orientação de respiração ou alinhamento mostrada ao lado do movimento enquanto alguém acompanha.',
						'Confira a duração estimada que o editor calcula para você e clique em **Salvar**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Os nomes de movimentos são sugeridos a partir dos seus planos anteriores enquanto você digita. Escolher uma sugestão mantém a mesma postura escrita do mesmo jeito em todo lugar.',
				},
			],
		},
		{
			heading: 'Vincular a uma aula',
			blocks: [
				{
					type: 'list',
					items: [
						'Ao criar uma aula, escolha o plano em **Plano de sessão**.',
						'Já criou a aula? Na página da aula, os organizadores clicam em **Vincular a um evento de aula** no cartão **Sequência da sessão**.',
					],
				},
				{
					type: 'p',
					text: 'Os participantes então veem a sequência completa na página da aula. Um plano privado continua privado para todos os demais, mas as pessoas de uma aula à qual você o vincula podem vê-lo.',
				},
			],
		},
		{
			heading: 'Acompanhar a sessão',
			blocks: [
				{
					type: 'p',
					text: 'Abra o plano e clique em **Iniciar sessão**. As posturas sustentadas e os flows cronometrados avançam sozinhos; nas repetições, clique em **Pronto** quando terminar. Você pode **Pausar**, **Retomar**, **Pular** uma etapa ou **Abandonar**. Quando você termina, a sessão é salva no seu registro de academia como um treino.',
				},
				{
					type: 'p',
					text: 'O app do celular executa o mesmo acompanhamento, lê as indicações em voz alta, mantém a tela ligada e continua contando o tempo se você mudar para outro app.',
				},
			],
		},
		{
			heading: 'Compartilhar o plano',
			blocks: [
				{
					type: 'list',
					items: [
						'**Tornar pública** permite que qualquer pessoa o encontre e acompanhe. **Copiar link de compartilhamento** torna o plano público e copia um link que funciona sem entrar na conta.',
						'**Publicar em um clube**: escolha o clube em **Escolha um clube…** e clique em **Publicar**. Ele aparece em **Modelos de sessão** na aba **Modelos** do clube, e os membros clicam em **Adotar** para ter a própria cópia.',
					],
				},
			],
		},
	],
	sources: {
		title: '2761214d4528b755',
		summary: '6ed93f306126bfd5',
		's0.heading': '75ab7687d1fdc4e6',
		's0.b0': '4c2393e2453c0847',
		's0.b1.i0': 'be6a427f8e3575ab',
		's0.b1.i1': '43033b89a725981f',
		's1.heading': 'd222e97495049181',
		's1.b0.i0': 'e1da2dcf855fd8cd',
		's1.b0.i1': '117837344c17aa7d',
		's1.b0.i2': '2e19d15f6adb30c7',
		's1.b0.i3': '4178a74d986586c6',
		's1.b0.i4': 'ba82220d774c7f84',
		's1.b0.i5': '03673097f36c78e9',
		's1.b0.i6': 'd02405ef4e9be33a',
		's1.b0.i7': '4f883b9f98fe5258',
		's1.b1': '63d86fc0ace9cb60',
		's2.heading': '27bf4831df1b4047',
		's2.b0.i0': '08f6e2680c9d0de7',
		's2.b0.i1': '91f068b693756ac2',
		's2.b1': '9021887b2281f1ca',
		's3.heading': '273869c12606c741',
		's3.b0': 'bfc8888c6226cf77',
		's3.b1': '4c67ea01c09f80f8',
		's4.heading': '692991f8b622c079',
		's4.b0.i0': '548fec5550dfaa6b',
		's4.b0.i1': '21ced8342dc5228c',
	},
};
