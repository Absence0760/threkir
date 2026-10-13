import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'link-ultrasignup-results',
	title: 'Associar os seus resultados do UltraSignup',
	summary: 'Encontre o seu perfil do UltraSignup pelo nome, confirme qual das pessoas corresponde a si e importe um resultado de ultra ou trail a partir do calendário de provas.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'A importação do UltraSignup só existe na web e está desligada até ser ativada. Se o cartão do UltraSignup não aparecer em Integrações, ou disser **A importação do UltraSignup ainda não está disponível. parkrun e a colagem manual continuam a funcionar.**, pode na mesma adicionar um resultado colando-o no calendário de provas.',
				},
				{
					type: 'p',
					text: 'O UltraSignup gere as inscrições e os resultados de muitas provas de trail e ultra. Associar o seu perfil uma vez significa que nunca mais tem de escrever o seu nome ou dorsal ao importar um resultado.',
				},
			],
		},
		{
			heading: 'Associar o seu perfil',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra [[route:/settings/integrations|Integrações]] nas Definições e encontre o cartão do UltraSignup.',
						'Em **Encontrar o seu perfil do UltraSignup**, introduza o seu **Nome próprio** e **Apelido** exatamente como se inscreve nas provas e, depois, selecione **Encontrar-me**.',
						'O UltraSignup lista todas as pessoas com esse nome. Use a idade, o número de resultados e as provas mais recentes de cada pessoa para se identificar.',
						'Em **Qual destes perfis é o seu?**, selecione **Sou eu** na sua entrada.',
					],
				},
				{
					type: 'p',
					text: 'O cartão mostra agora **Associado como** com o seu nome e o seu número do UltraSignup. Se escolheu a pessoa errada, selecione **Desassociar** e pesquise de novo. As corridas que já importou mantêm-se quando desassocia.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se vir **O UltraSignup não tem ninguém com esse nome. Confirme a grafia que usa nas inscrições.**, experimente a grafia exata das suas inscrições, incluindo qualquer nome do meio ou hífen.',
				},
			],
		},
		{
			heading: 'Importar um resultado do calendário de provas',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra [[route:/races|Provas]] e encontre a prova em que correu.',
						'Selecione **Importar o meu resultado**. O importador mostra em nome de quem está a importar.',
						'Confirme a importação. Só chega o seu próprio resultado nessa prova, identificado pelo id da prova no UltraSignup e pela data da prova.',
					],
				},
				{
					type: 'p',
					text: 'O resultado chega como uma corrida com o seu tempo oficial e as suas classificações. Se gravou a prova, abra antes essa corrida: quando corresponde a uma prova do calendário, a corrida pergunta se foi essa prova, e selecionar **Importar resultado** adiciona o resultado oficial à corrida que já tem, em vez de criar uma segunda.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Só são importados resultados de quem terminou, e uma prova cujo id ou data não coincida é ignorada em vez de adivinhada. Ainda há muito poucas provas do UltraSignup no calendário, por isso a sua pode não estar listada; use antes **Colar o seu resultado** no calendário de provas.',
				},
				{
					type: 'p',
					text: 'Se vir **Associe primeiro o seu perfil do UltraSignup nas Definições e depois importe a partir daqui.**, associe o seu perfil como acima e volte.',
				},
			],
		},
	],
	sources: {
		title: '1c3d3ccace74b014',
		summary: 'f2fca5922e80c09a',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '0c7ce54419de8a75',
		's0.b1': '44ce80029649ec21',
		's1.heading': '9585e27668c04a9f',
		's1.b0.i0': '5c97b00e1a40a36b',
		's1.b0.i1': 'c74c3876783d3d3e',
		's1.b0.i2': 'a2c9f8d1aa769e71',
		's1.b0.i3': '583ce1f06db5e7a3',
		's1.b1': '75c4a2aecaf4f626',
		's1.b2': 'a780f42937b826b1',
		's2.heading': '2beec2f1afabca9b',
		's2.b0.i0': 'b25aba40145c665f',
		's2.b0.i1': 'bd2e53852db627ea',
		's2.b0.i2': '6dce444ee6e264da',
		's2.b1': 'e5693507bec3f21c',
		's2.b2': '041b5d6a68e26cfe',
		's2.b3': '01220bce8ab2d8b5',
	},
};
