import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'race-day-for-hosts',
	title: 'Dia de prova para organizadores',
	summary: 'Prepare a prova, dê o GO, acompanhe ao vivo, encerre-a e depois aprove e corrija os resultados.',
	sections: [
		{
			heading: 'Quem pode conduzir uma prova',
			blocks: [
				{
					type: 'p',
					text: 'O controle da prova aparece na página do evento para os proprietários do clube, os administradores e os membros com a função **Diretor de prova**. Na web, é o cartão **Controle da corrida**; no app do celular, é o cartão **CONTROLE DA CORRIDA** na tela do evento. Nos dois é possível aprovar e editar resultados.',
				},
				{
					type: 'p',
					text: 'Antes, garanta que o evento tenha percursos — veja [[guide:set-up-a-race|Configurar uma prova]].',
				},
				{
					type: 'illustration',
					id: 'race-day-for-hosts',
					alt: 'O dia da prova em quatro passos, da esquerda para a direita: preparar a prova, dar o GO, acompanhar ao vivo e encerrá-la na chegada.',
				},
			],
		},
		{
			heading: '1. Preparar a prova',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o evento e escolha a ocorrência de hoje, se ele se repetir.',
						'Deixe **Aprovar automaticamente os resultados enviados** marcado para publicar os resultados conforme chegam, ou desmarque para aprovar cada um você mesmo. (No app do celular, aparece como **Aprovar automaticamente os tempos enviados**.)',
						'Escolha **Preparar corrida** quando todos estiverem reunidos.',
					],
				},
				{
					type: 'p',
					text: 'Os corredores que disseram **Eu vou** agora veem **Prova preparada** na aba Corrida do celular e “PROVA PREPARADA” no relógio Wear OS.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Preparada, a prova fica em espera. Nada é cronometrado e nenhum resultado pode ser salvo até você dar o GO.',
				},
			],
		},
		{
			heading: '2. Dar o GO',
			blocks: [
				{
					type: 'p',
					text: 'Clique em **JÁ** na web (**Disparar o Go** no app do celular) no momento em que a prova começar.',
				},
				{
					type: 'p',
					text: 'O horário de largada é registrado pelo nosso servidor, não pelo seu dispositivo, então é o mesmo tempo bruto para todos os corredores, mesmo que o relógio do seu celular esteja alguns segundos errado. O tempo bruto de cada corredor é medido a partir dele.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'O GO não inicia a gravação de ninguém. Os corredores pressionam Iniciar no próprio celular ou relógio, seja na linha de largada enquanto a prova está preparada (a gravação entra na prova no GO), seja depois de verem **Prova AO VIVO**. Lembre-os de iniciar uma gravação.',
				},
			],
		},
		{
			heading: '3. Acompanhar ao vivo',
			blocks: [
				{
					type: 'list',
					items: [
						'O cartão de controle da prova mostra **Em andamento** com o tempo decorrido.',
						'Escolha **Visão do espectador** para ver o mapa ao vivo, a classificação **No percurso** e a classificação **Concluído**. Veja [[guide:follow-a-race-live|Acompanhar uma prova ao vivo]].',
						'Os dispositivos dos corredores registram a chegada automaticamente na linha de chegada, então os resultados aparecem na página do evento enquanto a prova ainda está em andamento.',
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
						'Quando o último corredor chegar (ou o seu tempo de corte tiver passado), escolha **Encerrar corrida**.',
						'A confirmação, na web e no app do celular, informa quantos corredores que largaram estão sem resultado. Esses corredores serão marcados como DNF.',
						'Confirme com **Encerrar corrida**.',
					],
				},
				{
					type: 'p',
					text: 'Encerrar registra um DNF para cada corredor que enviou pelo menos uma posição ao vivo, mas não tem resultado, usando a distância e o tempo da última posição dele. Esses DNFs levam a marca de organizador. Os corredores que nunca começaram a gravar não recebem nenhum registro.',
				},
				{
					type: 'p',
					text: 'Um corredor cujo celular ou relógio estava sem sinal na chegada ainda pode enviar o resultado que ficou guardado por até 24 horas depois que você encerrar a prova, e ele substitui o DNF.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'O encerramento não pode ser desfeito. Depois de encerrada a prova, os dispositivos dos corredores deixam de esperar um resultado. Para correr a mesma ocorrência de novo, prepare uma nova sessão.',
				},
			],
		},
		{
			heading: 'Cancelamento',
			blocks: [
				{
					type: 'p',
					text: 'Você só pode cancelar enquanto a prova está preparada: escolha **Cancelar** ao lado de **JÁ** (**Disparar o Go** no app do celular) e depois **Cancelar corrida**. Depois que você dá o GO, a prova só pode ser encerrada.',
				},
				{
					type: 'p',
					text: 'O cancelamento não registra DNFs. A página do espectador informa que a prova foi cancelada pelo organizador, e os corredores veem que a prova terminou.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'O cancelamento não pode ser desfeito. Use **Encerrar corrida** se as pessoas realmente correram e você quer os resultados delas.',
				},
			],
		},
		{
			heading: 'Aprovar e editar os resultados',
			blocks: [
				{
					type: 'p',
					text: 'Os resultados ficam na página do evento, em **Resultados**, com uma classificação por percurso. No app do celular, cada resultado tem um menu com as mesmas ações **Aprovar**, **Remover verificação** e **Editar**.',
				},
				{
					type: 'list',
					items: [
						'Se a aprovação automática estava desativada, os novos resultados mostram **PENDENTE** e nenhuma colocação. Escolha **Aprovar** para publicar um deles. **Remover verificação** devolve um resultado aprovado para pendente.',
						'Para corrigir um resultado, escolha **Editar**, informe um **Tempo (h:mm:ss)** e um **Status** (**Concluiu**, **DNF** ou **DNS**) e depois **Salvar resultado**.',
						'Um resultado editado é marcado como **Editado pelo organizador**, para que todos vejam que ele foi alterado pelo organizador. A edição ajusta junto o tempo bruto do corredor.',
						'**Baixar resultados CSV** exporta as classificações.',
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
		's0.b2': '043bfb92b5287252',
	},
};
