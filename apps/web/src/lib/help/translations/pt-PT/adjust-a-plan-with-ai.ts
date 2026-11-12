import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'adjust-a-plan-with-ai',
	title: 'Ajustar um plano de treino com IA',
	summary: 'Descreva uma alteração ao seu plano por palavras suas, verifique cada alteração sugerida e guarde apenas quando concordar.',
	sections: [
		{
			heading: 'O que pode alterar',
			blocks: [
				{
					type: 'p',
					text: 'Ajustar com IA transforma um pedido como *passa a minha corrida longa para sábado* ou *torna a próxima semana mais leve* em alterações a um plano que guardou. Pode mudar um treino para outro dia da mesma semana, trocar dois dias, aumentar ou reduzir um pouco uma semana, transformar uma semana em semana de recuperação ou saltar um treino.',
				},
				{
					type: 'p',
					text: 'Cada alteração é feita pelas próprias regras de planos do Threkir. A IA nunca escreve um treino, uma distância ou um ritmo, por isso um pedido como *acrescenta um treino de subidas* recebe uma nota a dizer que isso não é possível. Para tudo o resto, use **Editar plano**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ajustar com IA só existe na web e pode ainda não estar ativado. Se **Ajustar com IA** não aparecer em **Ajustar plano**, não está disponível para si.',
				},
			],
		},
		{
			heading: 'Pedir uma alteração',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o seu plano na web e selecione **Ajustar plano**.',
						'Escolha **Ajustar com IA**.',
						'Escreva o que quer alterar e selecione **Sugerir alterações**.',
						'Leia as **Alterações sugeridas**: cada treino que muda de dia, é saltado ou fica mais leve, e cada objetivo semanal que muda, antes e depois.',
						'Selecione **Aplicar alterações sugeridas pela IA** para as guardar. Até lá, nada mudou no seu plano; selecione **Cancelar** para o deixar como estava.',
					],
				},
			],
		},
		{
			heading: 'Verificações de segurança antes de guardar',
			blocks: [
				{
					type: 'list',
					items: [
						'Alterações que levariam uma semana para a zona de risco elevado de lesão, face ao seu treino recente, não podem ser aplicadas. A página indica qual é a semana.',
						'Se as alterações tornarem uma semana mais exigente do que o seu treino recente suporta, ou puserem dois treinos duros em dias seguidos, é-lhe perguntado **Aplicar alterações mais exigentes?** e tem de escolher **Aplicar mesmo assim**.',
						'Uma sugestão que não podia ser aplicada em segurança é deixada de fora, e a página informa-o disso.',
					],
				},
			],
		},
		{
			heading: 'O que utiliza',
			blocks: [
				{
					type: 'list',
					items: [
						'Cada pedido gasta uma das suas mensagens diárias do Coach de IA, o mesmo limite do Coach.',
						'Precisa do aviso de IA mais recente. Se lhe pedirem para o aceitar, selecione **Reveja-o nas Definições** e aceite-o aí.',
						'Só os próximos treinos do seu plano e a alteração que escreveu são enviados para a IA.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Também pode pedir ao Coach para alterar o seu plano. Ele responde com um link que abre Ajustar com IA com o seu pedido já preenchido.',
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
