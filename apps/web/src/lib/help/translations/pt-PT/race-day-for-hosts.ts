import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-day-for-hosts',
	title: 'Dia de prova para organizadores',
	summary: 'Prepare a prova, dê a partida, acompanhe-a em direto, encerre-a e depois aprove e corrija os resultados.',
	sections: [
		{
			heading: 'Quem pode gerir uma prova',
			blocks: [
				{
					type: 'p',
					text: 'O controlo da prova aparece na página do evento para os proprietários e administradores do clube e para os membros com o papel **Diretor de prova**. Na web é o cartão **Controlo da corrida**; na app do telemóvel é o cartão **CONTROLO DA CORRIDA** no ecrã do evento. Ambos permitem aprovar e editar resultados.',
				},
				{
					type: 'p',
					text: 'Certifique-se primeiro de que o evento tem percursos — consulte [[guide:set-up-a-race|Configurar uma prova]].',
				},
			],
		},
		{
			heading: '1. Preparar a prova',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o evento e escolha a ocorrência de hoje, se o evento se repetir.',
						'Deixe **Aprovar automaticamente os resultados enviados** assinalado para publicar os resultados à medida que chegam, ou desmarque-o para aprovar cada um. (Na app do telemóvel diz **Aprovar automaticamente os tempos enviados**.)',
						'Escolha **Preparar corrida** quando estiverem todos reunidos.',
					],
				},
				{
					type: 'p',
					text: 'Os corredores que disseram **Eu vou** veem agora **Corrida preparada** no separador Corrida do telemóvel e “PROVA PRONTA” no relógio Wear OS.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Uma prova preparada está em espera. Nada é cronometrado e nenhum resultado pode ser guardado até dar a partida.',
				},
			],
		},
		{
			heading: '2. Dar a partida',
			blocks: [
				{
					type: 'p',
					text: 'Prima **JÁ** na web (**Disparar o Go** na app do telemóvel) no momento em que a prova começa.',
				},
				{
					type: 'p',
					text: 'A hora de partida é registada pelo nosso servidor, não pelo seu dispositivo, por isso é a mesma hora de partida oficial para todos os corredores, mesmo que o relógio do seu telemóvel esteja alguns segundos desacertado. O tempo bruto de cada corredor é medido a partir dela.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Dar a partida não inicia a gravação de ninguém. Os corredores premem Iniciar no próprio telemóvel ou relógio, seja na linha de partida enquanto a prova está preparada (a gravação entra na prova no momento da partida), seja depois de verem **Prova EM DIRETO**. Lembre-os de iniciar a gravação.',
				},
			],
		},
		{
			heading: '3. Acompanhar em direto',
			blocks: [
				{
					type: 'list',
					items: [
						'O cartão de controlo da prova mostra **A decorrer** com o tempo decorrido.',
						'Escolha **Visão do espectador** para ver o mapa em direto, o quadro **No percurso** e o quadro **Concluído**. Consulte [[guide:follow-a-race-live|Acompanhar uma prova em direto]].',
						'Os dispositivos dos corredores registam a chegada automaticamente na linha de meta, por isso os resultados aparecem na página do evento enquanto a prova ainda decorre.',
					],
				},
			],
		},
		{
			heading: '4. Encerrar a prova',
			blocks: [
				{
					type: 'steps',
					items: [
						'Quando o último corredor tiver chegado (ou o seu tempo limite tiver passado), escolha **Encerrar corrida**.',
						'A confirmação, na web e na app do telemóvel, diz-lhe quantos corredores que partiram não têm resultado. Esses corredores ficarão como DNF.',
						'Confirme com **Encerrar corrida**.',
					],
				},
				{
					type: 'p',
					text: 'Encerrar a prova regista um DNF para cada corredor que enviou pelo menos uma posição em direto mas não tem resultado, usando a distância e o tempo da sua última posição. Estes DNF levam a marca do organizador. Os corredores que nunca começaram a gravar não ficam com nada registado.',
				},
				{
					type: 'p',
					text: 'Um corredor cujo telemóvel ou relógio estava sem sinal na chegada pode ainda enviar um resultado em fila de espera até 24 horas depois de encerrar a prova, e esse resultado substitui o DNF.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Encerrar a prova não pode ser desfeito. Depois de encerrada, os dispositivos dos corredores deixam de esperar um resultado. Para voltar a disputar a mesma ocorrência, prepare uma nova sessão.',
				},
			],
		},
		{
			heading: 'Cancelar',
			blocks: [
				{
					type: 'p',
					text: 'Só pode cancelar enquanto a prova está preparada: escolha **Cancelar** ao lado de **JÁ** (**Disparar o Go** na app do telemóvel) e depois **Cancelar corrida**. Depois de dar a partida, a prova só pode ser encerrada.',
				},
				{
					type: 'p',
					text: 'Cancelar não regista nenhum DNF. A página do espectador diz que a prova foi cancelada pelo organizador, e os corredores veem que a prova terminou.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Cancelar não pode ser desfeito. Use antes **Encerrar corrida** se as pessoas chegaram a correr e quer os seus resultados.',
				},
			],
		},
		{
			heading: 'Aprovar e editar resultados',
			blocks: [
				{
					type: 'p',
					text: 'Os resultados estão na página do evento em **Resultados**, com um quadro por percurso. Na app do telemóvel, cada resultado tem um menu com as mesmas ações **Aprovar**, **Remover verificação** e **Editar**.',
				},
				{
					type: 'list',
					items: [
						'Se a aprovação automática estava desligada, os novos resultados mostram **PENDENTE** e nenhuma posição. Escolha **Aprovar** para publicar um. **Remover verificação** devolve um resultado aprovado ao estado pendente.',
						'Para corrigir um resultado, escolha **Editar**, introduza um **Tempo (h:mm:ss)** e um **Estado** (**Terminou**, **DNF** ou **DNS**) e depois **Guardar resultado**.',
						'Um resultado editado é marcado como **Editado pelo organizador**, para que todos vejam que foi alterado pelo organizador. A edição altera também o tempo bruto do corredor.',
						'**Transferir resultados CSV** exporta os quadros.',
					],
				},
			],
		},
	],
	sources: {
		title: '345bfeb73c862a63',
		summary: '68e18b9d83f2ca2d',
		's0.heading': '95b8e6a62cefca57',
		's0.b0': '7b081f765b2e73ec',
		's0.b1': '00aa52e26fec65b0',
		's1.heading': '0f3300a60c9bfa0b',
		's1.b0.i0': '7bdfd19fafd16a95',
		's1.b0.i1': 'b26a53d0fd770ca6',
		's1.b0.i2': 'db729ba4238dbf0f',
		's1.b1': '94ec2fea3c0890dc',
		's1.b2': '9b4a5aa61857cac1',
		's2.heading': 'bcda14674f57c276',
		's2.b0': '933b20b503e29bac',
		's2.b1': '656cb122eaf287fc',
		's2.b2': '65fce2c1be98450f',
		's3.heading': 'c3c4743c28e9dcc0',
		's3.b0.i0': 'aa6bba561bc42aea',
		's3.b0.i1': 'b8ecf8f3f5af1006',
		's3.b0.i2': '9874c56b87143c5f',
		's4.heading': '14dea53ae562634f',
		's4.b0.i0': '4bb0c3a5ddf2738a',
		's4.b0.i1': '9f2d97f9ea8e9cdf',
		's4.b0.i2': 'e63d194b0818af24',
		's4.b1': 'd9f0c880b9265d6c',
		's4.b2': 'eefbd14c075fb596',
		's4.b3': 'b067bfb6142d262b',
		's5.heading': '20d55e8c3373cb09',
		's5.b0': 'df971b2d64e7ef15',
		's5.b1': 'ba1729be79f60bc4',
		's5.b2': 'b10fb4196bd3e2ef',
		's6.heading': '27e65c3d7a252fc5',
		's6.b0': '982210c986719645',
		's6.b1.i0': 'a0e615efe581a71e',
		's6.b1.i1': '0bada1dfb7752ded',
		's6.b1.i2': 'dc555607c15c1ae0',
		's6.b1.i3': '12b5ecdf863972b3',
	},
};
