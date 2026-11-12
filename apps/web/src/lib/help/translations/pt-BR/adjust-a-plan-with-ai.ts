import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'adjust-a-plan-with-ai',
	title: 'Ajustar um plano de treino com IA',
	summary: 'Descreva uma mudança no seu plano com suas próprias palavras, confira cada alteração sugerida e salve só quando concordar.',
	sections: [
		{
			heading: 'O que dá para mudar',
			blocks: [
				{
					type: 'p',
					text: 'Ajustar com IA transforma um pedido como *muda meu longão para sábado* ou *deixa a próxima semana mais leve* em mudanças em um plano que você salvou. Ele pode mover um treino para outro dia da mesma semana, trocar dois dias, aumentar ou reduzir um pouco uma semana, transformar uma semana em semana de recuperação ou pular um treino.',
				},
				{
					type: 'p',
					text: 'Cada mudança é feita pelas próprias regras de planos do Threkir. A IA nunca escreve um treino, uma distância ou um pace, então um pedido como *coloca um treino de subida* recebe um aviso de que isso não é possível. Para todo o resto, use **Editar plano**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ajustar com IA só existe na web e talvez ainda não esteja ativado. Se **Ajustar com IA** não aparecer em **Ajustar plano**, ele não está disponível para você.',
				},
			],
		},
		{
			heading: 'Pedir uma mudança',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra seu plano na web e selecione **Ajustar plano**.',
						'Escolha **Ajustar com IA**.',
						'Digite o que você quer mudar e selecione **Sugerir mudanças**.',
						'Leia as **Mudanças sugeridas**: cada treino que muda de dia, é pulado ou fica mais leve, e cada meta semanal que muda, antes e depois.',
						'Selecione **Aplicar mudanças sugeridas pela IA** para salvá-las. Até lá, nada mudou no seu plano; selecione **Cancelar** para deixá-lo como estava.',
					],
				},
			],
		},
		{
			heading: 'Verificações de segurança antes de salvar',
			blocks: [
				{
					type: 'list',
					items: [
						'Mudanças que levariam uma semana para a faixa de alto risco de lesão, em relação ao seu treino recente, não podem ser aplicadas. A página diz qual é a semana.',
						'Se as mudanças deixarem uma semana mais puxada do que o seu treino recente aguenta, ou colocarem dois treinos fortes em dias seguidos, você vê a pergunta **Aplicar mudanças mais puxadas?** e precisa escolher **Aplicar mesmo assim**.',
						'Uma sugestão que não podia ser aplicada com segurança fica de fora, e a página avisa você.',
					],
				},
			],
		},
		{
			heading: 'O que ele usa',
			blocks: [
				{
					type: 'list',
					items: [
						'Cada pedido gasta uma das suas mensagens diárias do Coach de IA, o mesmo limite do Coach.',
						'Ele precisa do aviso de IA mais recente. Se pedirem que você o aceite, selecione **Revisar em Configurações** e aceite lá.',
						'Só os próximos treinos do seu plano e a mudança que você digitou são enviados para a IA.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Você também pode pedir ao Coach para mudar seu plano. Ele responde com um link que abre Ajustar com IA com o seu pedido já preenchido.',
				},
			],
		},
	],
	sources: {
		title: '3430390db6cef427',
		summary: '0b8f143261af9bcc',
		's0.heading': '44fa39d8b77c49be',
		's0.b0': '38fcc465ef1aec71',
		's0.b1': '7e6eec922334abd2',
		's0.b2': 'ca366aa955882170',
		's1.heading': 'f445fc4ffc97bebf',
		's1.b0.i0': '62be50b834eee366',
		's1.b0.i1': '490a29939b6ffad0',
		's1.b0.i2': '8dd005960648769c',
		's1.b0.i3': '6b71202d85d1ca61',
		's1.b0.i4': '1372a2a63c642a43',
		's2.heading': 'd9ef6a00bed5abfb',
		's2.b0.i0': '5b077f2018bffd38',
		's2.b0.i1': '2aae15cab49e816a',
		's2.b0.i2': 'aa84c731a647d1f3',
		's3.heading': '7e05806066a320c6',
		's3.b0.i0': '62c07e209d9ce339',
		's3.b0.i1': '1418c266b519f9d9',
		's3.b0.i2': '5de71e71f15f24a2',
		's3.b1': '12d00dbd647acb4c',
	},
};
