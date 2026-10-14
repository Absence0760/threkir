import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'build-a-session-plan',
	title: 'Criar um plano de sessão de ioga, pilates ou mobilidade',
	summary: 'Escreva uma sequência cronometrada de posturas, fluxos e repetições, com movimentos por lado e indicações, e depois dê aulas com ela, associe-a a uma aula e siga-a.',
	sections: [
		{
			heading: 'Onde criar o plano',
			blocks: [
				{
					type: 'p',
					text: 'Os planos de sessão escrevem-se na web. A app do telemóvel lista-os e executa-os, mas ainda não tem editor.',
				},
				{
					type: 'list',
					items: [
						'Para si: abra [[route:/plans/new|Novo plano]] e escolha **Plano de sessão**, ou prima **Nova sessão** em [[route:/sessions|Sessões]].',
						'Para o seu clube: no separador **Modelos** do clube, prima **Adicionar modelo** e escolha **Plano de sessão**. Fica imediatamente guardado como modelo do clube.',
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
						'Dê-lhe um **Título** que identifique a sequência, como “Fluxo de abertura da anca, 45 min”.',
						'Adicione uma **Disciplina** (por exemplo, ioga vinyasa) e o **Equipamento** que as pessoas devem ter à mão, como um tapete ou um reformer.',
						'Se quiser, prima **Adicionar bloco** para o dividir em secções como Aquecimento, De pé e Desaquecimento. Um plano sem blocos é executado de seguida, do início ao fim.',
						'Prima **Adicionar movimento** para cada postura ou exercício e escreva o nome em **Movimento**.',
						'Escolha o **Tipo**: **Sustentar** para uma postura cronometrada, **Flow** para uma sequência de movimento cronometrada, ou **Reps.** para um exercício contado. Depois introduza os **Segundos** ou as **Repetições** e o **Bloco** a que pertence.',
						'Marque **Por lado (esquerdo e direito)** para tudo o que se faz de cada lado. É executado uma vez para cada lado, por isso demora o dobro.',
						'Se quiser, adicione um **Tempo** e uma **Indicação**, a instrução de respiração ou alinhamento mostrada junto ao movimento enquanto alguém segue a sessão.',
						'Verifique a duração estimada que o editor calcula por si e prima **Guardar**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Os nomes dos movimentos são sugeridos a partir dos seus planos anteriores à medida que escreve. Escolher uma sugestão mantém a mesma postura escrita da mesma forma em todo o lado.',
				},
			],
		},
		{
			heading: 'Associar o plano a uma aula',
			blocks: [
				{
					type: 'list',
					items: [
						'Ao criar uma aula, escolha o plano em **Plano de sessão**.',
						'Já criou a aula? Na página da aula, os organizadores premem **Vincular a um evento de aula** no cartão **Sequência da sessão**.',
					],
				},
				{
					type: 'p',
					text: 'Os participantes veem então a sequência completa na página da aula. Um plano privado continua privado para todos os outros, mas as pessoas de uma aula à qual o associe podem vê-lo.',
				},
			],
		},
		{
			heading: 'Seguir a sessão',
			blocks: [
				{
					type: 'p',
					text: 'Abra o plano e prima **Iniciar sessão**. As posturas e os fluxos cronometrados avançam sozinhos; nas repetições, prima **Pronto** quando terminar. Pode **Pausar**, **Retomar**, **Saltar** um passo ou **Abandonar**. Quando termina, a sessão fica guardada no seu registo de ginásio como treino.',
				},
				{
					type: 'p',
					text: 'A app do telemóvel faz o mesmo acompanhamento, lê as indicações em voz alta, mantém o ecrã ligado e continua a contar o tempo se mudar para outra app.',
				},
			],
		},
		{
			heading: 'Partilhar o plano',
			blocks: [
				{
					type: 'list',
					items: [
						'**Tornar pública** permite que qualquer pessoa o encontre e siga. **Copiar link de partilha** torna o plano público e copia um link que funciona sem iniciar sessão.',
						'**Publicar num clube**: escolha o clube em **Escolha um clube…** e prima **Publicar**. Aparece em **Modelos de sessão** no separador **Modelos** do clube, e os membros premem **Adotar** para obter a sua própria cópia.',
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
