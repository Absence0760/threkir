import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'racing-in-a-race',
	title: 'Correr numa prova em direto',
	summary: 'Inscreva-se, escolha o seu percurso, comece a gravar antes da linha de partida e deixe o telemóvel ou o relógio cronometrá-lo desde a linha de partida até à linha de chegada.',
	sections: [
		{
			heading: 'Com que dispositivos pode competir',
			blocks: [
				{
					type: 'list',
					items: [
						'App do telemóvel Android: suporte total. Mostra o aviso da prova, envia a sua posição em direto e cronometra-o pelas linhas de partida e de chegada.',
						'App para iPhone: executa o mesmo código que a do Android, mas ainda não foi testada num iPhone numa prova real.',
						'Relógio Wear OS: suporte total no pulso, incluindo a cronometragem pelas linhas. A inscrição e a escolha do percurso continuam a ser feitas na web ou no telemóvel.',
						'Apple Watch: apenas suporte inicial. Mostra o aviso da prova, envia a sua posição e comunica o seu tempo através do iPhone, mas não deteta as linhas de partida e de chegada, por isso não tem chegada automática, e ainda não foi comprovado numa prova real. Leve o telemóvel como alternativa, ou volte a cronometrar o seu resultado a partir do seu trajeto na web depois da prova.',
						'Web: use-a para se inscrever, escolher um percurso, ver resultados e voltar a cronometrar um resultado a partir do trajeto de uma corrida. Um navegador não consegue gravar uma corrida.',
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
			heading: 'Prova preparada e Prova EM DIRETO',
			blocks: [
				{
					type: 'p',
					text: 'Quando o organizador prepara a prova, o separador Corrida da app do telemóvel mostra **Prova preparada** com “a aguardar o GO”. O relógio Wear OS mostra “PROVA PREPARADA” por cima do botão Iniciar. Quando o organizador dá o GO, passa a **Prova EM DIRETO** (“PROVA EM DIRETO” no relógio), com o tempo decorrido e “toque em Iniciar”.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'O telemóvel ou o relógio não começa a gravar sozinho: tem de premir Iniciar antes de chegar à linha de partida. Pode começar enquanto a prova mostra **Prova preparada**, ou quando vir **Prova EM DIRETO**. Uma gravação iniciada antes entra na prova no GO, no telemóvel e num relógio Wear OS.',
				},
				{
					type: 'p',
					text: 'A app do telemóvel procura as provas a que disse **Eu vou** e que começam no prazo de um dia. Se o aviso demorar a aparecer, mantenha a app aberta no separador Corrida durante um minuto.',
				},
			],
		},
		{
			heading: 'Atravessar a linha de partida',
			blocks: [
				{
					type: 'p',
					text: 'Quando o seu percurso tem linha de partida, o ecrã de corrida mostra a que distância está, por exemplo “120 m até à linha de partida”. Atravesse-a no sentido do percurso. Depois do GO, o telemóvel ou o relógio Wear OS vibra, diz “Linha de partida atravessada, a cronometrar” se os avisos de voz estiverem ativos, e o seu tempo de chip conta a partir desse momento.',
				},
				{
					type: 'list',
					items: [
						'Já passou a linha de partida quando soa o GO? A sua partida é o próprio GO.',
						'Atravessar a linha antes do GO, por exemplo durante o aquecimento, não conta. Depois do GO, a sua partida conta quando tiver avançado cerca de 50 m no percurso sem voltar a atravessar a linha.',
						'Se o telemóvel ou o relógio nunca o vir atravessar a linha de partida, o seu tempo de chip conta a partir do momento em que premiu Iniciar.',
					],
				},
			],
		},
		{
			heading: 'Chegada automática',
			blocks: [
				{
					type: 'p',
					text: 'Não precisa de premir nada na meta. Quando o seu percurso tem linha de chegada, o telemóvel ou o relógio Wear OS regista a sua chegada no momento em que a atravessa no sentido do percurso, desde que já tenha percorrido o suficiente do percurso: 60% da distância desde que atravessou a linha de partida, ou 90% quando não foi detetada nenhuma passagem pela linha de partida. Isto impede que um percurso em circuito, que começa onde termina, registe a sua chegada logo à saída.',
				},
				{
					type: 'p',
					text: 'Passar ao lado da linha de chegada, por um caminho paralelo, não conta, porque nunca a atravessa. O seu tempo é registado no momento em que atravessou a linha. O telemóvel vibra e mostra “Meta cortada!” com o seu tempo oficial.',
				},
				{
					type: 'p',
					text: 'Um percurso com ponto de chegada mas sem linha de chegada mantém a regra anterior: termina quando estiver a 30 m ou menos da chegada e tiver percorrido 90% do percurso, com o tempo registado no momento em que esteve mais perto dela. Num percurso com linha de chegada, esse círculo de 30 m só conta se premir Parar ou **Terminar prova** dentro dele.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Não há chegada automática se o seu percurso não tiver distância, não tiver linha nem ponto de chegada, ou tiver uma rota que atravessa a própria linha de chegada antes do fim, como acontece num percurso de voltas. Use Parar e depois **Terminar prova** quando atravessar a linha.',
				},
			],
		},
		{
			heading: 'Não terminou? Retomar',
			blocks: [
				{
					type: 'p',
					text: 'Uma chegada pela linha é enviada de imediato e a gravação fica em pausa. Durante os 60 segundos seguintes, o ecrã de corrida oferece **Não terminou? Retomar**, no telemóvel e num relógio Wear OS. Se ainda não terminou, por exemplo porque atravessou a linha antes do tempo numa volta, toque nele: o seu resultado é retirado e a gravação continua. Se não fizer nada, a gravação para e o resultado mantém-se.',
				},
				{
					type: 'p',
					text: 'Depois de anular uma chegada, termine o resto da prova manualmente: toque em Parar e depois em **Terminar prova** quando terminar de facto. Se a app reiniciar antes disso, volta a vigiar a linha de chegada, mas nunca conta a chegada que anulou.',
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
					text: 'Num relógio Wear OS, o ecrã de pausa oferece “Vai” para retomar, e mantenha premido **Fim** para terminar.',
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
			heading: 'Tempo oficial, tempo de chip e partidas tardias',
			blocks: [
				{
					type: 'list',
					items: [
						'O **Tempo oficial** conta desde o momento em que o organizador deu o GO até à sua chegada. É o tempo pelo qual é classificado.',
						'O **Tempo de chip** conta desde que atravessou a linha de partida até à sua chegada. Se não foi detetada nenhuma passagem pela linha de partida, conta a partir de quando premiu Iniciar, ou a partir do GO se premiu Iniciar antes. Nunca é maior do que o seu tempo oficial.',
						'Se começar mais de 5 minutos depois do GO, ou se a sua primeira posição estiver a mais de 200 m do início do percurso, a app do telemóvel mostra um aviso de partida tardia e um relógio Wear OS mantém **Partida tardia** por baixo do relógio da prova. O seu tempo oficial continua a contar a partir do GO, por isso uma partida tardia torna-o maior do que o seu tempo de chip.',
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
					text: 'Se o organizador encerrar a prova antes de chegar à meta, o telemóvel avisa-o e o relógio mostra “Prova encerrada”. A sua corrida continua a ser gravada como uma corrida normal, mas o dispositivo não envia nenhum resultado da prova. Se já tinha enviado uma posição em direto, a prova marca-o como DNF.',
				},
			],
		},
	],
	sources: {
		title: '3ce73ee9613bf595',
		summary: '8a84191c960f3189',
		's0.heading': 'ac0fdba8f9fafc40',
		's0.b0.i0': '5f9d1c45bcbbfb31',
		's0.b0.i1': 'c4096345432d33e6',
		's0.b0.i2': '547cdcc69e247581',
		's0.b0.i3': 'f068efe69456ba52',
		's0.b0.i4': '13822228d183e2b0',
		's1.heading': 'f00c55d7857a6dce',
		's1.b0.i0': '30eeadd878d7b098',
		's1.b0.i1': '525a552fd753b987',
		's1.b0.i2': '9efc1bb52d90e6ef',
		's1.b1': '55c32b3a7d7a241c',
		's2.heading': 'ed31d49e898938c8',
		's2.b0': 'f4ff1ecc36a2cf8e',
		's2.b1': 'b77e8bc9d60c9032',
		's2.b2': 'ddeff25fbc81b659',
		's3.heading': '3a0b0b0d9f43041c',
		's3.b0': '521195c2168d7fda',
		's3.b1.i0': '90b0261b0ce9c3f1',
		's3.b1.i1': 'a8d5dd7d6540cf62',
		's3.b1.i2': '8984cdb2a3694851',
		's4.heading': 'b1c0468dde456524',
		's4.b0': '900f305519a8032c',
		's4.b1': '32f9e651e83644d2',
		's4.b2': 'b39f1ce0d4a09d1a',
		's4.b3': '0e408636f1230c3b',
		's5.heading': 'bfa00064941be0cc',
		's5.b0': '86c65402c413b22d',
		's5.b1': 'a71d2963bd840180',
		's6.heading': '5df934589d491767',
		's6.b0': 'f1a6d8c09124a7d8',
		's6.b1.i0': '7a35b26309af9c5b',
		's6.b1.i1': 'f2cbc2dc9b04ff5b',
		's6.b1.i2': '630eba7ef0538b75',
		's6.b2': 'a0e378aecf393dda',
		's6.b3': 'b99b4c432279d3ea',
		's7.heading': '19cee1ff0ce4a9e3',
		's7.b0': 'b44459cc78b71aaf',
		's8.heading': 'b26ffa9d3d25af83',
		's8.b0.i0': '5aa5f4e57b72adfb',
		's8.b0.i1': '43b664e01ad5869b',
		's8.b0.i2': 'ce8974750a19dc0f',
		's8.b1': '1a0778a6029af8ae',
		's9.heading': '8cfcf517e30f6408',
		's9.b0': 'e103d457341fcf30',
	},
};
