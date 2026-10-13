import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'invite-members-and-roles',
	title: 'Convidar membros e atribuir-lhes papéis',
	summary: 'Partilhe um link de convite, aprove pedidos de adesão e atribua a membros de confiança o papel de administrador, organizador de eventos ou diretor de prova.',
	sections: [
		{
			heading: 'Como as pessoas entram',
			blocks: [
				{
					type: 'p',
					text: 'A forma como alguém entra depende da política de adesão do clube, que escolheu ao criá-lo e pode alterar com **Editar clube** na web.',
				},
				{
					type: 'list',
					items: [
						'**Qualquer pessoa pode entrar**: as pessoas selecionam **Entrar no clube** na página do clube e ficam logo dentro.',
						'**Requer aprovação**: as pessoas selecionam **Solicitar entrada** e aguardam numa fila até um administrador as aprovar.',
						'**Apenas por convite**: as pessoas precisam de um link de convite de um administrador.',
					],
				},
			],
		},
		{
			heading: 'Partilhar um link de convite',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o seu clube na web. Quando o clube é **Apenas por convite**, os administradores veem um painel **Link de convite** na página do clube.',
						'Selecione **Gerar link de convite** da primeira vez e depois **Copiar** para pôr o link na área de transferência.',
						'Envie o link como quiser. Quem o abrir e iniciar sessão entra no clube como membro.',
					],
				},
				{
					type: 'p',
					text: 'Se um link se espalhou mais do que queria, selecione **Renovar**. É criado um novo link e o antigo deixa de funcionar imediatamente.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Um link de convite deixa as pessoas entrar diretamente: salta a fila de aprovação, por isso partilhe-o apenas com pessoas que tem gosto em admitir. Se o clube exigir o reconhecimento dos riscos da atividade, o link pede-o antes de deixar alguém entrar.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Na app do telemóvel, um membro também pode tocar em **Entrar com código de convite** no separador **Clubes** de **Social** e colar o link completo ou apenas o código depois de /clubs/join/. Abrir o link no navegador do telemóvel também funciona.',
				},
			],
		},
		{
			heading: 'Aprovar ou rejeitar pedidos de adesão',
			blocks: [
				{
					type: 'p',
					text: 'Quando o clube exige aprovação, os administradores veem **Pedidos pendentes** com uma contagem ao lado.',
				},
				{
					type: 'list',
					items: [
						'Na web, selecione **Aprovar** ou **Rejeitar** em cada pedido, ou **Aprovar todas** quando houver vários à espera. Rejeitar pede-lhe primeiro uma confirmação.',
						'Na app do telemóvel, abra o separador **Membros** do clube e toque em **Aprovar** ou **Recusar** em cada pedido.',
					],
				},
			],
		},
		{
			heading: 'Atribuir um papel aos membros',
			blocks: [
				{
					type: 'p',
					text: 'Cada clube tem um **Proprietário**, a pessoa que o criou. As outras pessoas podem ter um destes papéis:',
				},
				{
					type: 'list',
					items: [
						'**Administrador**: altera as definições do clube, gere os membros e os seus papéis, gere eventos e provas e aprova resultados.',
						'**Organizador de eventos**: cria, edita e elimina eventos e adiciona participantes, sem acesso às definições nem aos membros do clube.',
						'**Diretor de prova**: prepara, dá a partida e termina provas, e aprova ou rejeita resultados.',
						'**Membro**: publica respostas, confirma presença em eventos e envia os seus próprios resultados de provas.',
					],
				},
				{
					type: 'steps',
					items: [
						'Abra o seu clube na web e escolha o separador **Membros**.',
						'Use o menu de papéis ao lado de um membro para escolher o novo papel. A alteração é guardada de imediato.',
						'Para retirar alguém do clube, use o botão de remover ao lado dessa pessoa e confirme.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Por agora, alterar papéis e remover membros só é possível na web. O separador **Membros** da app do telemóvel mostra o número de membros e os pedidos pendentes, não a lista completa.',
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
