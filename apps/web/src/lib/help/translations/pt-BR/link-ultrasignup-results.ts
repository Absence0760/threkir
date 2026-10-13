import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'link-ultrasignup-results',
	title: 'Vincular seus resultados do UltraSignup',
	summary: 'Encontre o seu perfil do UltraSignup pelo nome, confirme qual pessoa é você e depois importe um resultado de ultra ou trail pelo calendário de provas.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'A importação do UltraSignup é só na web e fica desativada até ser habilitada. Se o cartão do UltraSignup não aparecer em Integrações, ou disser **A importação do UltraSignup ainda não está disponível. O parkrun e a colagem manual continuam funcionando.**, você ainda pode adicionar um resultado colando-o no calendário de provas.',
				},
				{
					type: 'p',
					text: 'O UltraSignup cuida das inscrições e dos resultados de muitas provas de trail e ultra. Vincular o seu perfil uma vez significa que você nunca mais digita o seu nome ou número de peito ao importar um resultado.',
				},
			],
		},
		{
			heading: 'Vincular seu perfil',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra [[route:/settings/integrations|Integrações]] em Configurações e encontre o cartão do UltraSignup.',
						'Em **Encontre o seu perfil do UltraSignup**, digite o seu **Nome** e **Sobrenome** exatamente como você usa nas inscrições e selecione **Encontrar**.',
						'O UltraSignup lista todas as pessoas com esse nome. Use a idade, o número de resultados e as provas mais recentes de cada uma para se encontrar.',
						'Em **Qual destas pessoas é você?**, selecione **Sou eu** na sua entrada.',
					],
				},
				{
					type: 'p',
					text: 'O cartão agora mostra **Vinculado como** com o seu nome e o seu número no UltraSignup. Se você escolheu a pessoa errada, selecione **Desvincular** e pesquise de novo. As corridas que você já importou continuam quando você desvincula.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se aparecer **O UltraSignup não tem ninguém com esse nome. Confira a grafia que você usa nas inscrições.**, tente a grafia exata das suas inscrições em provas, incluindo nomes do meio ou hífens.',
				},
			],
		},
		{
			heading: 'Importar um resultado do calendário de provas',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra [[route:/races|Corridas]] e encontre a prova que você correu.',
						'Selecione **Importar meu resultado**. O importador mostra em nome de quem está importando.',
						'Confirme a importação. Só o seu próprio resultado daquela prova é trazido, identificado pelo id da prova no UltraSignup e pela data da prova.',
					],
				},
				{
					type: 'p',
					text: 'O resultado chega como uma corrida com o seu tempo oficial e as suas classificações. Se você mesmo gravou a prova, abra essa corrida: quando ela corresponde a uma prova do calendário, a corrida pergunta se foi aquela prova, e selecionar **Importar resultado** adiciona o resultado oficial à corrida que você já tem, em vez de criar uma segunda.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Só são importados resultados de quem concluiu a prova, e uma prova cujo id ou data não corresponde é ignorada em vez de adivinhada. Pouquíssimas provas do UltraSignup estão no calendário por enquanto, então a sua prova pode não estar listada; nesse caso, use **Colar seu resultado** no calendário de provas.',
				},
				{
					type: 'p',
					text: 'Se aparecer **Vincule primeiro o seu perfil do UltraSignup em Configurações e depois importe por aqui.**, vincule o seu perfil como descrito acima e volte.',
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
