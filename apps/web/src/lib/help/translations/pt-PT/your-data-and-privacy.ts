import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'your-data-and-privacy',
	title: 'Os seus dados e a sua privacidade',
	summary: 'Veja o que as outras pessoas podem ver, escolha quem vê as novas corridas, transfira tudo o que guardamos sobre si e elimine a sua conta.',
	sections: [
		{
			heading: 'O que as outras pessoas podem ver',
			blocks: [
				{
					type: 'list',
					items: [
						'A sua página de perfil, com o seu nome de apresentação, fotografia, número de seguidores e as suas corridas públicas, pode ser aberta por qualquer pessoa que tenha o link. Com um perfil privado, só os seguidores que aprovar veem as suas corridas e listas de seguidores; consulte [[guide:private-profile-and-follow-requests|Tornar o seu perfil privado e aprovar seguidores]].',
						'As corridas que tornar públicas aparecem no seu perfil e no feed. As corridas privadas só são visíveis para si.',
						'A sua participação num clube público, e tudo o que publicar nele, pode ser vista por quem pode ver o clube.',
						'Enquanto partilha um link em direto, a corrida em curso pode ser vista por qualquer pessoa com o link.',
						'Uma fotografia que marque com **Mostrar na página da prova**, numa corrida pública associada a uma prova, aparece na página pública dessa prova com a legenda e o seu nome. Desmarque-a, ou torne a corrida privada, para a retirar.',
					],
				},
				{
					type: 'p',
					text: 'As zonas de privacidade cortam o início e o fim dos seus trajetos sempre que outra pessoa os vê. Consulte [[guide:privacy-zones|Esconder a sua casa com zonas de privacidade]].',
				},
			],
		},
		{
			heading: 'Escolher quem vê as novas corridas',
			blocks: [
				{
					type: 'steps',
					items: [
						'Na web, abra [[route:/settings/privacy|Privacidade e partilha]] nas Definições e escolha uma **Visibilidade predefinida para novas corridas**. Na app do telemóvel, é **Privacidade predefinida das corridas** em **Preferências**, no separador **Tu**.',
						'Para alterar uma única corrida mais tarde, abra-a e use **Tornar pública** ou **Tornar privada**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Só **Público** torna as novas corridas visíveis para os outros. As corridas ainda não têm uma opção só para seguidores, por isso escolher seguidores como predefinição mantém as novas corridas privadas, e os seus seguidores não as verão.',
				},
				{
					type: 'list',
					items: [
						'**Mostrar-me na pesquisa por nome**: desative para manter a sua conta fora das pesquisas por nome. O seu perfil e as suas corridas públicas continuam a poder ser abertos por qualquer pessoa que tenha o link.',
						'**Mostrar-me em Corredores por perto**, onde estiver disponível: desativado por predefinição. Quando está ativado, os corredores perto da área que definir podem encontrá-lo. Só é guardada uma área aproximada, nunca a sua localização em direto.',
					],
				},
			],
		},
		{
			heading: 'Transferir os seus dados',
			blocks: [
				{
					type: 'p',
					text: 'Na web, abra **Conta** nas Definições. A app do telemóvel tem as mesmas opções em **Conta**, no separador **Tu**.',
				},
				{
					type: 'list',
					items: [
						'**Transferir ficheiro completo da conta** (no telemóvel, **Exportação da conta**): tudo o que guardamos sobre si, incluindo conversas com o treinador, mensagens, integrações e contactos de segurança, num único zip. É gerado no nosso servidor, por isso pode fechar a página e voltar mais tarde para o obter. Uma exportação concluída é mantida durante 7 dias.',
						'**Transferir backup completo** (no telemóvel, **Backup completo**): todas as corridas com o respetivo trajeto GPS, mais as suas rotas, perfil e preferências, num ficheiro que pode restaurar mais tarde com **Restaurar de um backup**.',
						'**Exportação na nuvem (zip GPX)**: um ficheiro GPX por corrida, com frequência cardíaca, pronto a importar noutras apps. As contas gratuitas podem exportar duas vezes por hora; as contas Pro, oito vezes.',
						'**Exportar todas as corridas (CSV)** (no telemóvel, **Exportar corridas como CSV**): uma linha por corrida para uma folha de cálculo, sem trajetos GPS.',
					],
				},
			],
		},
		{
			heading: 'Eliminar a sua conta',
			blocks: [
				{
					type: 'steps',
					items: [
						'Transfira primeiro tudo o que quiser guardar. A eliminação não pode ser desfeita.',
						'Na web, abra **Conta** nas Definições e selecione **Eliminar conta** em **Zona de perigo**. Na app do telemóvel, abra **Conta** no separador **Tu** e toque em **Eliminar conta**.',
						'Escreva ELIMINAR para confirmar e depois selecione **Eliminar a minha conta** na web ou **Eliminar** na app.',
					],
				},
				{
					type: 'p',
					text: 'Isto remove permanentemente a sua conta, corridas, rotas, trajetos, participações em clubes e preferências dos nossos servidores. Num telemóvel, as corridas guardadas no próprio dispositivo ficam lá até iniciar sessão como outra pessoa ou remover a app.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Não consegue entrar na app? [[route:/delete-account|Eliminar a sua conta]] explica como pedir a eliminação sem ela.',
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
