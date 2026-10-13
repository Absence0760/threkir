import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'invite-members-and-roles',
	title: 'Convidar membros e atribuir funções',
	summary: 'Compartilhe um link de convite, aprove solicitações de entrada e dê a membros de confiança a função de administrador, organizador de eventos ou diretor de prova.',
	sections: [
		{
			heading: 'Como as pessoas entram',
			blocks: [
				{
					type: 'p',
					text: 'A forma de entrar depende da política de adesão do clube, que você escolheu ao criá-lo e pode mudar com **Editar clube** na web.',
				},
				{
					type: 'list',
					items: [
						'**Qualquer pessoa pode entrar**: as pessoas selecionam **Entrar no clube** na página do clube e entram na hora.',
						'**Requer aprovação**: as pessoas selecionam **Solicitar entrada** e esperam em uma fila até que um administrador as aprove.',
						'**Somente por convite**: as pessoas precisam de um link de convite de um administrador.',
					],
				},
			],
		},
		{
			heading: 'Compartilhar um link de convite',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o seu clube na web. Quando o clube é **Somente por convite**, os administradores veem um painel **Link de convite** na página do clube.',
						'Selecione **Gerar link de convite** na primeira vez e depois **Copiar** para colocar o link na área de transferência.',
						'Envie o link como preferir. Quem abrir o link e entrar na conta passa a ser membro do clube.',
					],
				},
				{
					type: 'p',
					text: 'Se um link se espalhou mais do que você queria, selecione **Renovar**. Um novo link é criado e o antigo para de funcionar na hora.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Um link de convite deixa as pessoas entrarem direto: ele pula a fila de aprovação, então compartilhe-o só com quem você aceita receber. Se o clube exige o reconhecimento dos riscos da atividade, o link pede esse reconhecimento antes de deixar alguém entrar.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'No app para celular, um membro também pode tocar em **Entrar com código de convite** na aba **Clubes** de **Social** e colar o link inteiro ou só o código depois de /clubs/join/. Abrir o link no navegador do celular também funciona.',
				},
			],
		},
		{
			heading: 'Aprovar ou rejeitar solicitações de entrada',
			blocks: [
				{
					type: 'p',
					text: 'Quando o clube exige aprovação, os administradores veem **Solicitações pendentes** com a contagem ao lado.',
				},
				{
					type: 'list',
					items: [
						'Na web, selecione **Aprovar** ou **Rejeitar** em cada solicitação, ou **Aprovar todas** quando houver várias esperando. Rejeitar pede que você confirme antes.',
						'No app para celular, abra a aba **Membros** do clube e toque em **Aprovar** ou **Recusar** em cada solicitação.',
					],
				},
			],
		},
		{
			heading: 'Atribuir uma função aos membros',
			blocks: [
				{
					type: 'p',
					text: 'Todo clube tem um **Proprietário**, a pessoa que o criou. Outras pessoas podem ter uma destas funções:',
				},
				{
					type: 'list',
					items: [
						'**Administrador**: muda as configurações do clube, gerencia os membros e as funções deles, conduz eventos e provas e aprova resultados.',
						'**Organizador de eventos**: cria, edita e exclui eventos e adiciona participantes, sem acesso às configurações nem aos membros do clube.',
						'**Diretor de prova**: prepara, inicia e encerra provas e aprova ou rejeita resultados.',
						'**Membro**: publica respostas, confirma presença em eventos e envia os próprios resultados de prova.',
					],
				},
				{
					type: 'steps',
					items: [
						'Abra o seu clube na web e escolha a aba **Membros**.',
						'Use o menu de função ao lado de um membro para escolher a nova função. A mudança é salva na hora.',
						'Para tirar alguém do clube, use o botão de remover ao lado da pessoa e confirme.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Mudar funções e remover membros, por enquanto, só é possível na web. A aba **Membros** do app para celular mostra o número de membros e as solicitações pendentes, não a lista completa.',
				},
			],
		},
	],
	sources: {
		title: '7a795179c19e9ede',
		summary: '6bd8f063f9b47e9c',
		's0.heading': 'a0b11759509dec45',
		's0.b0': '6373b2a85a1609f6',
		's0.b1.i0': 'ee27e4b5847787d3',
		's0.b1.i1': 'b3ca923e10bea1a6',
		's0.b1.i2': '43f232607a69a9eb',
		's1.heading': 'ff3fad2f072540f7',
		's1.b0.i0': '53bc4c42c338a50b',
		's1.b0.i1': '527bae1b53082d53',
		's1.b0.i2': '7717031f30823ba7',
		's1.b1': '71a8c58fdf04e4c7',
		's1.b2': 'ac04b52b16128c47',
		's1.b3': '95001612b9e89408',
		's2.heading': 'ac0d31b6960aec87',
		's2.b0': '5e020c1365ade658',
		's2.b1.i0': '001fdb020367ef82',
		's2.b1.i1': '8a13349f6280affe',
		's3.heading': '5ae9577e9c45959a',
		's3.b0': '6b88528b0352a4ca',
		's3.b1.i0': '4a654fadcb92a4e9',
		's3.b1.i1': '4fb82402d20e5ae6',
		's3.b1.i2': '99c1319e71b4efe7',
		's3.b1.i3': 'd2c28cf99bce668b',
		's3.b2.i0': '8552b807ede6b519',
		's3.b2.i1': '12d66025f3fdd53b',
		's3.b2.i2': '2bc7dca0194195b4',
		's3.b3': '2dbf13356f8d50fe',
	},
};
