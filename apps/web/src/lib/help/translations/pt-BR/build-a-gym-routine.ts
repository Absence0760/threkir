import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'build-a-gym-routine',
	title: 'Montar uma rotina de academia',
	summary: 'Transforme um treino que você ensina ou repete em uma rotina reutilizável com séries, repetições, carga, descanso e superséries, e depois execute-a guiada ou compartilhe-a com seu clube.',
	sections: [
		{
			heading: 'Duas formas de começar',
			blocks: [
				{
					type: 'list',
					items: [
						'Do zero: abra [[route:/gym/routines|Rotinas]] e clique em **Nova rotina**. Na web você também pode ir em [[route:/plans/new|Novo plano]] e escolher **Rotina de academia**.',
						'A partir de um treino que você já registrou: abra-o no seu registro de academia e clique em **Salvar como rotina**. Os exercícios e as séries dele viram as metas da rotina. Já **Repetir o último** inicia um novo registro a partir do mesmo treino.',
					],
				},
				{
					type: 'p',
					text: 'No app do celular, abra a tela de academia e toque em **Rotinas** e depois em **Nova rotina**.',
				},
			],
		},
		{
			heading: 'Preencher a rotina',
			blocks: [
				{
					type: 'steps',
					items: [
						'Dê à rotina um **Nome da rotina** que se refira ao dia, e não ao primeiro exercício, por exemplo “Bootcamp A”.',
						'Digite o nome do primeiro exercício. Reaproveite um nome que você já registra, para que seus recordes desse exercício fiquem num só lugar.',
						'Escolha como ele é **Medido por**: peso e repetições, peso corporal, tempo ou distância. As linhas de série mudam para pedir a meta correspondente.',
						'Para cada série, informe um **Tipo de série** e as metas, como **Repetições-alvo** e peso, e um **Descanso (s)**. Clique em **Adicionar série** para incluir mais séries.',
						'Para fazer dois exercícios em sequência, sem pausa, ative **Supersérie com o próximo exercício** no primeiro deles.',
						'Clique em **Adicionar exercício** para o próximo e repita.',
						'Se quiser, abra **Avançado** e escolha uma regra de **Progressão**, que sugere os números da próxima sessão a partir do resultado desta. Deixando em Nenhuma, suas metas ficam exatamente como foram digitadas.',
						'Adicione as **Notas (opcional)** que quiser e clique em **Salvar rotina**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Cada linha de série é uma meta, não um registro. É com ela que uma sessão iniciada a partir da rotina é preenchida, e você ainda pode mudar os números durante o treino.',
				},
			],
		},
		{
			heading: 'Executar a rotina',
			blocks: [
				{
					type: 'p',
					text: 'Abra a rotina e clique em **Iniciar rotina** (no app do celular, **Iniciar sessão**). Você é guiado uma série por vez, com a meta na tela: registre o que fez e clique em **Concluir série** ou em **Pular série**, com um cronômetro de descanso entre as séries. Clique em **Finalizar** no fim, e a sessão é salva no seu registro de academia com a comparação com o plano.',
				},
			],
		},
		{
			heading: 'Compartilhar com uma turma',
			blocks: [
				{
					type: 'list',
					items: [
						'**Publicar em um clube**: escolha o clube em **Escolha um clube…** e clique em **Publicar**. Ela aparece na aba **Modelos** desse clube, em **Modelos de rotina de academia**, onde os membros clicam em **Adotar** para ter a própria cópia. Alterações em uma cópia não mudam o seu original.',
						'**Publicar na biblioteca pública**: qualquer pessoa conectada pode visualizá-la e adotá-la. Seus treinos registrados continuam privados.',
					],
				},
				{
					type: 'p',
					text: 'Vai dar uma aula paga com base na rotina? Veja [[guide:host-a-paid-gym-class|Oferecer uma aula paga de HIIT, força ou bootcamp]].',
				},
			],
		},
	],
	sources: {
		title: 'e154719ab6c6db3a',
		summary: 'c15dfd024f683826',
		's0.heading': 'a52411b1c11cf590',
		's0.b0.i0': '83c54adc1d0ea60f',
		's0.b0.i1': 'eecbf0bc154dab9e',
		's0.b1': '8f85ecd63a29a0a3',
		's1.heading': 'd222e97495049181',
		's1.b0.i0': '81da95efe111f60e',
		's1.b0.i1': '2d229299f8d76acb',
		's1.b0.i2': '82dd1ff342d922c0',
		's1.b0.i3': '5361d720e294f93d',
		's1.b0.i4': 'eadce6bf2e1f99a2',
		's1.b0.i5': '8e0bc50c1d08b6c7',
		's1.b0.i6': '47f7b227af1d250a',
		's1.b0.i7': '2a9bb2561495600e',
		's1.b1': '52bd55355e109053',
		's2.heading': '958ca26c6a61f02f',
		's2.b0': 'f393e332c6ec9a52',
		's3.heading': 'aab7baa90c561d6b',
		's3.b0.i0': 'd51e222a02a3c044',
		's3.b0.i1': 'fc99e8218cc68a71',
		's3.b1': '28cc92b70c319919',
	},
};
