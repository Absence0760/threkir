import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'build-a-gym-routine',
	title: 'Criar uma rotina de ginásio',
	summary: 'Transforme um treino que ensina ou repete numa rotina reutilizável com séries, repetições, carga, descanso e superséries, e depois execute-a com orientação ou partilhe-a com o seu clube.',
	sections: [
		{
			heading: 'Duas formas de começar',
			blocks: [
				{
					type: 'list',
					items: [
						'Do zero: abra [[route:/gym/routines|Rotinas]] e prima **Nova rotina**. Na web, também pode ir a [[route:/plans/new|Novo plano]] e escolher **Rotina de ginásio**.',
						'A partir de um treino que já registou: abra-o no seu registo de ginásio e prima **Guardar como rotina**. Os exercícios e as séries passam a ser os objetivos da rotina. **Repetir o último**, por sua vez, inicia um novo registo a partir do mesmo treino.',
					],
				},
				{
					type: 'p',
					text: 'Na app do telemóvel, abra o ecrã do ginásio e toque em **Rotinas** e depois em **Nova rotina**.',
				},
			],
		},
		{
			heading: 'Preencher a rotina',
			blocks: [
				{
					type: 'steps',
					items: [
						'Dê-lhe um **Nome da rotina** que identifique o dia e não o primeiro exercício, por exemplo “Bootcamp A”.',
						'Escreva o nome do primeiro exercício. Reutilize um nome que já usa nos seus registos, para que os seus recordes desse exercício fiquem num só lugar.',
						'Escolha em **Medido por** como o exercício é medido: peso e repetições, peso corporal, tempo ou distância. As linhas das séries mudam para pedir o objetivo correspondente.',
						'Para cada série, indique um **Tipo de série** e os seus objetivos, como **Repetições-alvo** e peso, e um **Descanso (s)**. Prima **Adicionar série** para acrescentar séries.',
						'Para fazer dois exercícios seguidos, sem pausa, ative **Supersérie com o próximo exercício** no primeiro.',
						'Prima **Adicionar exercício** para o seguinte e repita.',
						'Se quiser, abra **Avançado** e escolha uma regra de **Progressão**, que sugere os números da sessão seguinte a partir do resultado desta. Se ficar em Nenhuma, os seus objetivos mantêm-se exatamente como os escreveu.',
						'Adicione **Notas (opcional)** se quiser e prima **Guardar rotina**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Cada linha de série é um objetivo, não um registo. É com isso que é preenchida uma sessão iniciada a partir da rotina, e pode continuar a alterar os números à medida que avança.',
				},
			],
		},
		{
			heading: 'Executar a rotina',
			blocks: [
				{
					type: 'p',
					text: 'Abra a rotina e prima **Iniciar rotina** (na app do telemóvel, **Iniciar sessão**). É guiado uma série de cada vez, com o seu objetivo à vista: registe o que fez e prima **Concluir série**, ou **Ignorar série**, com um temporizador de descanso entre séries. Prima **Finalizar** no fim e a sessão é guardada no seu registo de ginásio, com a comparação com o plano.',
				},
			],
		},
		{
			heading: 'Partilhar a rotina com uma aula',
			blocks: [
				{
					type: 'list',
					items: [
						'**Publicar num clube**: escolha o clube em **Escolha um clube…** e prima **Publicar**. Aparece no separador **Modelos** desse clube, em **Modelos de rotina de ginásio**, onde os membros premem **Adotar** para obter a sua própria cópia. As alterações a uma cópia não mudam o seu original.',
						'**Publicar na biblioteca pública**: qualquer pessoa com sessão iniciada pode pré-visualizá-la e adotá-la. Os seus treinos registados continuam privados.',
					],
				},
				{
					type: 'p',
					text: 'Vai dar uma aula paga com base na rotina? Consulte [[guide:host-a-paid-gym-class|Organizar uma aula paga de HIIT, força ou bootcamp]].',
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
