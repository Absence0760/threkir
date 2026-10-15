import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'your-data-and-privacy',
	title: 'Seus dados e sua privacidade',
	summary: 'Veja o que as outras pessoas podem ver, escolha quem vê as novas corridas, baixe tudo o que temos sobre você e exclua a sua conta.',
	sections: [
		{
			heading: 'O que as outras pessoas podem ver',
			blocks: [
				{
					type: 'list',
					items: [
						'A sua página de perfil, com o seu nome de exibição, foto, contagens de seguidores e as suas corridas públicas, pode ser aberta por qualquer pessoa que tenha o link. Com um perfil privado, só os seguidores que você aprova veem suas corridas e listas de seguidores; veja [[guide:private-profile-and-follow-requests|Deixar seu perfil privado e aprovar seguidores]].',
						'As corridas que você torna públicas aparecem no seu perfil e no feed. As corridas privadas ficam visíveis só para você.',
						'A participação em um clube público, e tudo o que você publica nele, pode ser vista por quem pode ver o clube.',
						'Enquanto você compartilha um link ao vivo, a corrida em andamento pode ser vista por qualquer pessoa que tenha o link.',
						'Uma foto que você marca com **Mostrar na página da corrida**, em uma corrida pública vinculada a uma prova, aparece na página pública dessa prova com a legenda e o seu nome. Desmarque-a, ou deixe a corrida privada, para tirá-la de lá.',
					],
				},
				{
					type: 'p',
					text: 'As zonas de privacidade cortam o início e o fim dos seus trajetos onde quer que outra pessoa os veja. Veja [[guide:privacy-zones|Esconder sua casa com zonas de privacidade]].',
				},
			],
		},
		{
			heading: 'Escolher quem vê as novas corridas',
			blocks: [
				{
					type: 'steps',
					items: [
						'Na web, abra [[route:/settings/privacy|Privacidade e compartilhamento]] em Configurações e escolha uma **Visibilidade padrão para novas corridas**. No app para celular, é **Privacidade padrão das corridas** em **Preferências**, na aba **Você**.',
						'Para mudar uma única corrida depois, abra-a e use **Tornar público** ou **Tornar privado**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Só **Público** torna as novas corridas visíveis para outras pessoas. As corridas ainda não têm uma opção só para seguidores, então escolher seguidores como padrão mantém as novas corridas privadas, e os seus seguidores não vão vê-las.',
				},
				{
					type: 'list',
					items: [
						'**Exibir-me na busca por nome**: desative para manter a sua conta fora das buscas por nome. O seu perfil e as suas corridas públicas ainda podem ser abertos por qualquer pessoa que tenha o link.',
						'**Mostrar-me em Corredores por perto**, onde estiver disponível: desativado por padrão. Quando ativado, corredores perto da área que você definiu podem encontrar você. Só uma área aproximada é armazenada, nunca a sua localização em tempo real.',
					],
				},
			],
		},
		{
			heading: 'Baixar seus dados',
			blocks: [
				{
					type: 'p',
					text: 'Na web, abra **Conta** em Configurações. O app para celular tem as mesmas opções em **Conta**, na aba **Você**.',
				},
				{
					type: 'list',
					items: [
						'**Baixar arquivo completo da conta** (no celular, **Exportação da conta**): tudo o que temos sobre você, incluindo conversas com o treinador, mensagens, integrações e contatos de segurança, em um único zip. Ele é gerado no nosso servidor, então você pode fechar a página e voltar para buscá-lo depois. Uma exportação concluída fica guardada por 7 dias.',
						'**Baixar backup completo** (no celular, **Backup completo**): todas as corridas com o trajeto de GPS, além das suas rotas, perfil e preferências, em um arquivo que você pode restaurar depois com **Restaurar de um backup**.',
						'**Exportação na nuvem (zip GPX)**: um arquivo GPX por corrida, com frequência cardíaca, pronto para importar em outros apps. Contas gratuitas podem exportar duas vezes por hora; contas Pro, oito vezes.',
						'**Exportar todas as corridas (CSV)** (no celular, **Exportar corridas como CSV**): uma linha por corrida para uma planilha, sem os trajetos de GPS.',
					],
				},
			],
		},
		{
			heading: 'Excluir sua conta',
			blocks: [
				{
					type: 'steps',
					items: [
						'Baixe antes tudo o que quiser guardar. A exclusão não pode ser desfeita.',
						'Na web, abra **Conta** em Configurações e selecione **Excluir conta** em **Zona de perigo**. No app para celular, abra **Conta** na aba **Você** e toque em **Excluir conta**.',
						'Digite EXCLUIR para confirmar e depois selecione **Excluir minha conta** na web ou **Excluir** no app.',
					],
				},
				{
					type: 'p',
					text: 'Isso remove permanentemente dos nossos servidores a sua conta, corridas, rotas, trajetos, participações em clubes e preferências. Em um celular, as corridas armazenadas no próprio dispositivo continuam lá até você entrar com outra conta ou remover o app.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Não consegue acessar o app? [[route:/delete-account|Excluir sua conta]] explica como pedir a exclusão sem ele.',
				},
			],
		},
	],
	sources: {
		title: 'd180bf422ce3bba9',
		summary: '2b4cc5410b0eb4b6',
		's0.heading': '4158a516fb61f91b',
		's0.b0.i0': '6ef16a07f5e1d2dc',
		's0.b0.i1': '9a700fce5a4094fc',
		's0.b0.i2': 'dc76446c63a054d2',
		's0.b0.i3': '483ea8dba216e43c',
		's0.b0.i4': 'cc3a91ab3dc6a2a6',
		's0.b1': '0bbe7c39a03a9a09',
		's1.heading': 'ac353e580fc0908f',
		's1.b0.i0': '7b3a2d8b5b822576',
		's1.b0.i1': '1c68d368acdbf5ae',
		's1.b1': 'bdd9bb09bf384ad6',
		's1.b2.i0': 'aab065e45ac34e20',
		's1.b2.i1': 'af52470fc68dc9fb',
		's2.heading': 'fdbb4b35c4c483a4',
		's2.b0': 'c99f3ecf63b1a523',
		's2.b1.i0': '8c4857178e5dd3a5',
		's2.b1.i1': 'f4e6bebd7857fbbf',
		's2.b1.i2': 'c951ce9065ab0b67',
		's2.b1.i3': '6411af4fff4994ab',
		's3.heading': '7ab60595358e5d64',
		's3.b0.i0': '1ff19ec591d3e32c',
		's3.b0.i1': '4875a916b34863e4',
		's3.b0.i2': '830592d994cabb71',
		's3.b1': '28c0738abf26e30b',
		's3.b2': '4abf7820527a0449',
	},
};
