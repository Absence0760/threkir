import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'create-a-club',
	title: 'Criar um clube',
	summary: 'Crie um clube para o seu grupo de corrida, escolha quem o pode encontrar e como as pessoas entram, e publique o seu primeiro evento.',
	sections: [
		{
			heading: 'Na web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra [[route:/social|Social]] e escolha o separador **Clubes**.',
						'Selecione **Criar clube**.',
						'Preencha o **Nome**. Os membros procuram o clube por este nome, e o endereço web do clube é criado a partir dele quando cria o clube. Mudar o nome do clube mais tarde não altera esse endereço.',
						'Adicione uma **Descrição** e uma **Localização**, se quiser. Ambas são opcionais, mas uma localidade e um país em **Localização** ajudam os corredores das redondezas a encontrá-lo quando pesquisam na sua própria região.',
						'Escolha uma **Visibilidade**: com **Público**, o clube aparece em **Explorar**; com **Privado**, fica oculto e as pessoas só podem entrar através de um link de convite.',
						'Em **Quem pode entrar?**, escolha **Qualquer pessoa pode entrar**, **Requer aprovação** ou **Apenas por convite**.',
						'Assinale **Exigir o reconhecimento dos riscos da atividade para entrar** se quiser que cada novo membro confirme que compreende os riscos das corridas em grupo. Isto só pode ser definido agora, enquanto o clube está a ser criado.',
						'Selecione **Criar clube**. É levado para a página do novo clube, e passa a ser o seu proprietário.',
					],
				},
			],
		},
		{
			heading: 'Na app do telemóvel',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o separador **Social** e escolha **Clubes**.',
						'Toque em **Novo clube**.',
						'Introduza um **Nome** e, opcionalmente, uma **Descrição (opcional)** e uma **Localização (opcional)**.',
						'Escolha **Público** ou **Privado** e depois uma **Política de adesão**: **Aberto — qualquer um entra**, **Pedido — os administradores aprovam** ou **Apenas por convite**.',
						'Toque em **Criar**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'O reconhecimento dos riscos da atividade e os links para o site e as redes sociais do clube só podem ser definidos na web.',
				},
			],
		},
		{
			heading: 'Depois de o criar',
			blocks: [
				{
					type: 'p',
					text: 'A página do seu clube tem separadores para **Feed**, **Eventos**, **Rotas**, **Modelos**, **Fotografias** e **Membros**. Como proprietário, pode publicar atualizações no feed, adicionar eventos e gerir os membros.',
				},
				{
					type: 'list',
					items: [
						'Para alterar mais tarde o nome, a descrição, a visibilidade, a política de adesão ou os links, abra o clube na web e selecione **Editar clube**.',
						'Para adicionar a sua primeira corrida em grupo, selecione **Novo evento** na web, ou toque em **Criar evento** no separador **Eventos** na app do telemóvel.',
						'Para trazer pessoas, consulte [[guide:invite-members-and-roles|Convidar membros e atribuir-lhes papéis]].',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Eliminar um clube remove todos os seus eventos, publicações e membros para toda a gente, e não pode ser desfeito.',
				},
			],
		},
	],
	sources: {
		title: 'ff916040a4a088ae',
		summary: '90e58c1ce029b9f8',
		's0.heading': '1e1b85a2667ca4d5',
		's0.b0.i0': '81704e449355f8cb',
		's0.b0.i1': 'acfe56320dd5fa86',
		's0.b0.i2': '8f5ed6e368636764',
		's0.b0.i3': '0b33c70ca105f651',
		's0.b0.i4': 'ac21a20e9c83b3b8',
		's0.b0.i5': '7d3a8a5850778a1a',
		's0.b0.i6': '8a20a1b7087f8a35',
		's0.b0.i7': '019cb8b4c6074fbe',
		's1.heading': 'f21eaef94c685b5c',
		's1.b0.i0': 'ecd88baa3a8b6dfe',
		's1.b0.i1': 'fe76ba21da4f039b',
		's1.b0.i2': '2cc7185287318c16',
		's1.b0.i3': '4bd544b513ee23e9',
		's1.b0.i4': '42d0b5b43ab9db8b',
		's1.b1': '8cc57f936798f492',
		's2.heading': '6620415f4bf77118',
		's2.b0': 'a1a749aa3fcf7a85',
		's2.b1.i0': 'a21817fe350e546b',
		's2.b1.i1': '102566e11462e84f',
		's2.b1.i2': '83bc170018336efe',
		's2.b2': 'eb88a7323310e67e',
	},
};
