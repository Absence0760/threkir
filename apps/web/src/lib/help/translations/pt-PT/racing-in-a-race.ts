import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'racing-in-a-race',
	title: 'Correr numa prova em direto',
	summary: 'Inscreva-se, escolha o seu percurso, comece a gravar na linha de partida ou depois da partida e deixe o telemóvel ou o relógio cronometrá-lo até à meta.',
	sections: [
		{
			heading: 'Com que dispositivos pode competir',
			blocks: [
				{
					type: 'list',
					items: [
						'App do telemóvel Android: suporte total. Mostra o aviso da prova, envia a sua posição em direto e regista a sua chegada automaticamente.',
						'App para iPhone: executa o mesmo código que a do Android, mas ainda não foi testada num iPhone numa prova real.',
						'Relógio Wear OS: suporte total no pulso, incluindo a chegada automática. A inscrição e a escolha do percurso continuam a ser feitas na web ou no telemóvel.',
						'Apple Watch: apenas suporte inicial. Mostra o aviso da prova, envia a sua posição e comunica o seu tempo através do iPhone, mas não tem chegada automática e ainda não foi comprovado numa prova real. Leve o telemóvel como alternativa.',
						'Web: use-a para se inscrever, escolher um percurso e ver resultados. Um navegador não consegue gravar uma corrida.',
					],
				},
			],
		},
		{
			heading: 'Inscrever-se e escolher um percurso',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o evento da prova.',
						'Se houver mais do que um percurso, escolha o seu em **O seu percurso** na web. Na app do telemóvel, aparece **Escolha o seu percurso** quando toca em **Eu vou**.',
						'Toque em **Eu vou**. Só uma inscrição **Eu vou** recebe os avisos da prova no seu dispositivo; **Talvez** não.',
					],
				},
				{
					type: 'p',
					text: 'Mudou de ideias? Na web, escolha outro percurso em **O seu percurso** (verá “Percurso atualizado.”). Na app do telemóvel, toque em **Mudar de percurso**. Decida o seu percurso antes de começar a gravar: o telemóvel ou o relógio lê-o quando a gravação da prova começa, e o seu resultado vai para o quadro desse percurso.',
				},
			],
		},
		{
			heading: 'Prova pronta e Prova EM DIRETO',
			blocks: [
				{
					type: 'p',
					text: 'Quando o organizador prepara a prova, o separador Corrida da app do telemóvel mostra **Corrida preparada** com “a aguardar a partida”. O relógio Wear OS mostra “PROVA PRONTA” por cima do botão Iniciar. Quando o organizador dá a partida, passa a **Prova EM DIRETO** (“PROVA EM DIRETO” no relógio), com o tempo decorrido e “toque em Iniciar”.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'O telemóvel ou o relógio não começa a gravar sozinho: tem de premir Iniciar. Pode começar na linha de partida enquanto a prova mostra **Corrida preparada**, ou quando vir **Prova EM DIRETO**. Uma gravação iniciada antes entra na prova no momento da partida, no telemóvel e num relógio Wear OS, e o seu tempo líquido passa a contar a partir da partida e não de quando premiu Iniciar.',
				},
				{
					type: 'p',
					text: 'A app do telemóvel procura as provas a que disse **Eu vou** e que começam no prazo de um dia. Se o aviso demorar a aparecer, mantenha a app aberta no separador Corrida durante um minuto.',
				},
			],
		},
		{
			heading: 'Chegada automática',
			blocks: [
				{
					type: 'p',
					text: 'Não precisa de premir nada na meta. O telemóvel ou o relógio Wear OS regista a sua chegada quando estas duas condições se verificam:',
				},
				{
					type: 'list',
					items: [
						'está a 30 m ou menos da linha de meta, e',
						'percorreu pelo menos 90% da distância do seu percurso.',
					],
				},
				{
					type: 'p',
					text: 'O seu tempo é registado no momento em que esteve mais perto da meta, não no primeiro momento em que ficou a 30 m. A regra dos 90% impede que um percurso em circuito, que começa onde termina, registe a sua chegada logo no primeiro segundo. O telemóvel mostra “Meta cortada!” com o seu tempo bruto, e a gravação para.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se o seu percurso não tiver rota ou não tiver distância, não há chegada automática. Use Parar e depois **Terminar prova** quando cruzar a linha.',
				},
			],
		},
		{
			heading: 'Parar durante a prova',
			blocks: [
				{
					type: 'p',
					text: 'Durante uma prova em direto, Parar não termina a sua prova. Pausa a gravação e mostra **Prova em pausa**. O relógio da prova continua a contar.',
				},
				{
					type: 'list',
					items: [
						'**Retomar prova** continua a gravação.',
						'**Terminar prova** termina a sua prova agora. Se percorreu pelo menos 90% do percurso, é uma chegada manual nesse momento.',
						'Abaixo dos 90%, o botão diz **Terminar como DNF**, e terminar regista um DNF.',
					],
				},
				{
					type: 'p',
					text: 'Num relógio Wear OS, o ecrã de pausa oferece “Vai” para retomar, e mantém premido **Fim** para terminar.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Terminar antes de 90% do percurso regista um DNF. Se só parou para apertar um atacador, escolha **Retomar prova**.',
				},
			],
		},
		{
			heading: 'Sem sinal na meta',
			blocks: [
				{
					type: 'p',
					text: 'As linhas de meta têm muitas vezes pouco sinal. O telemóvel e o relógio Wear OS guardam primeiro o seu resultado e enviam-no assim que voltam a ligar-se, por isso não se perde. Tem de nos chegar no prazo de 24 horas depois de o organizador encerrar a prova. Não termine sessão na app antes de o resultado ser enviado.',
				},
			],
		},
		{
			heading: 'Tempo bruto, tempo líquido e partidas tardias',
			blocks: [
				{
					type: 'list',
					items: [
						'O **Tempo bruto** conta desde o momento em que o organizador deu a partida até à sua chegada. É o tempo pelo qual é classificado.',
						'O **Tempo líquido** conta desde que premiu Iniciar até à sua chegada, incluindo eventuais pausas. Se premiu Iniciar antes da partida, conta a partir da partida, por isso nunca é maior do que o seu tempo bruto.',
						'Se começar mais de 5 minutos depois da partida, ou se a sua primeira posição estiver a mais de 200 m do início do percurso, a app do telemóvel mostra um aviso de partida tardia. O seu tempo bruto continua a contar a partir da partida, por isso uma partida tardia torna-o maior do que o seu tempo líquido.',
					],
				},
				{
					type: 'p',
					text: 'Mais sobre como ler o quadro em [[guide:race-results-explained|Perceber os resultados das provas]].',
				},
			],
		},
		{
			heading: 'Se o organizador encerrar a prova primeiro',
			blocks: [
				{
					type: 'p',
					text: 'Se o organizador encerrar a prova antes de chegar à meta, o telemóvel avisa-o e o relógio mostra “Corrida terminada”. A sua corrida continua a ser gravada como uma corrida normal, mas o dispositivo não envia nenhum resultado da prova. Se já tinha enviado uma posição em direto, a prova marca-o como DNF.',
				},
			],
		},
	],
	sources: {
		title: '3ce73ee9613bf595',
		summary: '68756b47ced58dbe',
		's0.heading': 'ac0fdba8f9fafc40',
		's0.b0.i0': 'a9ea22844fb2d329',
		's0.b0.i1': 'c4096345432d33e6',
		's0.b0.i2': 'eb58207e7be0195c',
		's0.b0.i3': '1bcd7ec3984d3f4b',
		's0.b0.i4': 'ef48ea3447ed4a81',
		's1.heading': 'f00c55d7857a6dce',
		's1.b0.i0': '30eeadd878d7b098',
		's1.b0.i1': '525a552fd753b987',
		's1.b0.i2': '9efc1bb52d90e6ef',
		's1.b1': '55c32b3a7d7a241c',
		's2.heading': 'ed31d49e898938c8',
		's2.b0': 'f4ff1ecc36a2cf8e',
		's2.b1': '75851b29576f9617',
		's2.b2': 'ddeff25fbc81b659',
		's3.heading': 'b1c0468dde456524',
		's3.b0': '3b0504a88d8b1324',
		's3.b1.i0': 'd77e68893353ede5',
		's3.b1.i1': '56f20f41366f1cfa',
		's3.b2': 'e2edf18b6d5204ad',
		's3.b3': 'f25312164622198b',
		's4.heading': '5df934589d491767',
		's4.b0': 'f1a6d8c09124a7d8',
		's4.b1.i0': '7a35b26309af9c5b',
		's4.b1.i1': 'f2cbc2dc9b04ff5b',
		's4.b1.i2': '630eba7ef0538b75',
		's4.b2': 'a0e378aecf393dda',
		's4.b3': 'b99b4c432279d3ea',
		's5.heading': '19cee1ff0ce4a9e3',
		's5.b0': 'b44459cc78b71aaf',
		's6.heading': 'b26ffa9d3d25af83',
		's6.b0.i0': '5aa5f4e57b72adfb',
		's6.b0.i1': '323f02b7ad1e355d',
		's6.b0.i2': '6de66d3c548f93ae',
		's6.b1': '1a0778a6029af8ae',
		's7.heading': '8cfcf517e30f6408',
		's7.b0': 'e103d457341fcf30',
	},
};
