import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'racing-in-a-race',
	title: 'Correr uma prova ao vivo',
	summary: 'Inscreva-se, escolha seu percurso, comece a gravar antes da linha de largada e deixe seu celular ou relógio cronometrar você da linha de largada até a linha de chegada.',
	sections: [
		{
			heading: 'Quais dispositivos funcionam em provas',
			blocks: [
				{
					type: 'list',
					items: [
						'App para Android: suporte completo. Mostra o banner da prova, envia sua posição ao vivo e cronometra você pelas linhas de largada e chegada.',
						'App para iPhone: roda o mesmo código do Android, mas ainda não foi testado em um iPhone em uma prova real.',
						'Relógio Wear OS: suporte completo no pulso, incluindo a cronometragem pelas linhas. Você ainda se inscreve e escolhe seu percurso na web ou no celular.',
						'Apple Watch: apenas suporte inicial. Mostra o banner da prova, envia sua posição e informa seu tempo pelo iPhone, mas não detecta as linhas de largada e chegada, então não tem chegada automática, e ainda não foi comprovado em uma prova real. Leve o celular como reserva ou, depois, recronometre seu resultado pelo seu trajeto na web.',
						'Web: use para se inscrever, escolher um percurso, ver os resultados e recronometrar um resultado pelo trajeto de uma corrida. Um navegador não consegue gravar uma corrida.',
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
						'Se houver mais de um percurso, escolha o seu em **Seu percurso** na web. No app do celular, aparece **Escolha seu percurso** quando você toca em **Eu vou**.',
						'Toque em **Eu vou**. Só uma inscrição com **Eu vou** recebe os alertas da prova no seu dispositivo; **Talvez** não recebe.',
					],
				},
				{
					type: 'p',
					text: 'Mudou de ideia? Na web, escolha outro percurso em **Seu percurso** (você verá “Percurso atualizado.”). No app do celular, toque em **Trocar de percurso**. Defina seu percurso antes de começar a gravar: seu celular ou relógio o lê quando a gravação da prova começa, e seu resultado vai para a classificação desse percurso.',
				},
			],
		},
		{
			heading: 'Prova preparada e Prova AO VIVO',
			blocks: [
				{
					type: 'p',
					text: 'Quando o organizador prepara a prova, a aba Corrida do app do celular mostra **Prova preparada** com “aguardando o GO”. O relógio Wear OS mostra “PROVA PREPARADA” acima do botão Iniciar. Quando o organizador dá o GO, isso muda para **Prova AO VIVO** (“PROVA AO VIVO” no relógio), com o tempo decorrido e “toque em Iniciar”.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Seu celular ou relógio não começa a gravar sozinho: pressione Iniciar você mesmo, antes de chegar à linha de largada. Você pode começar enquanto a prova mostra **Prova preparada**, ou quando vir **Prova AO VIVO**. Uma gravação iniciada antes entra na prova no GO, no celular e no relógio Wear OS.',
				},
				{
					type: 'p',
					text: 'O app do celular verifica as provas em que você disse **Eu vou** e que começam em até um dia. Se o banner demorar a aparecer, mantenha o app aberto na aba Corrida por um minuto.',
				},
			],
		},
		{
			heading: 'Cruzar a linha de largada',
			blocks: [
				{
					type: 'p',
					text: 'Quando seu percurso tem uma linha de largada, a aba Corrida mostra a que distância ela está, por exemplo “120 m até a linha de largada”. Passe por ela no sentido do percurso. Depois do GO, seu celular ou relógio Wear OS vibra, diz “Linha de largada cruzada, cronometrando” se os avisos de voz estiverem ativados, e seu tempo líquido passa a contar a partir desse momento.',
				},
				{
					type: 'list',
					items: [
						'Já tinha passado da linha de largada quando foi dado o GO? Sua largada é o próprio GO.',
						'Cruzar a linha antes do GO, por exemplo durante o aquecimento, não conta. Depois do GO, sua largada conta quando você já avançou cerca de 50 m no percurso sem voltar a cruzar a linha.',
						'Se seu celular ou relógio nunca detectar você cruzando a linha de largada, seu tempo líquido passa a contar a partir de quando você pressionou Iniciar.',
					],
				},
			],
		},
		{
			heading: 'Chegada automática',
			blocks: [
				{
					type: 'p',
					text: 'Você não precisa pressionar nada na chegada. Quando seu percurso tem uma linha de chegada, seu celular ou relógio Wear OS registra sua chegada no momento em que você passa por ela no sentido do percurso, desde que já tenha coberto o suficiente do percurso: 60% da distância desde que cruzou a linha de largada, ou 90% quando nenhum cruzamento da linha de largada foi detectado. Isso evita que um percurso em circuito, que começa onde termina, registre sua chegada logo na saída.',
				},
				{
					type: 'p',
					text: 'Passar ao lado da linha de chegada, por um caminho paralelo, não conta, porque você nunca passa por ela. Seu tempo é registrado no momento em que você cruzou a linha. O celular vibra e mostra “Chegada!” com o seu tempo bruto.',
				},
				{
					type: 'p',
					text: 'Um percurso com ponto de chegada, mas sem linha de chegada, mantém a regra antiga: sua chegada é registrada quando você está a até 30 m da chegada e cobriu 90% do percurso, com o tempo do momento em que você esteve mais perto dela. Em um percurso com linha de chegada, esse círculo de 30 m só conta se você pressionar Parar ou **Finalizar prova** dentro dele.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Não há chegada automática se o seu percurso não tem distância, não tem nem linha nem ponto de chegada, ou tem uma rota que cruza a própria linha de chegada antes do fim, como um percurso de voltas. Use Parar e depois **Finalizar prova** quando cruzar a linha.',
				},
			],
		},
		{
			heading: 'Não terminou? Retomar',
			blocks: [
				{
					type: 'p',
					text: 'Uma chegada pela linha é enviada na hora e sua gravação é pausada. Nos 60 segundos seguintes, a aba Corrida oferece **Não terminou? Retomar**, no celular e no relógio Wear OS. Se você não terminou, por exemplo porque cruzou a linha antes da hora em uma volta, toque nele: seu resultado é retirado e a gravação continua. Se você não fizer nada, a gravação para e o resultado vale.',
				},
				{
					type: 'p',
					text: 'Depois de desfazer uma chegada, termine o resto da prova manualmente: toque em Parar e depois em **Finalizar prova** quando realmente terminar. Se o app reiniciar antes disso, ele volta a observar a linha de chegada, mas nunca conta a chegada que você desfez.',
				},
			],
		},
		{
			heading: 'Parar durante a prova',
			blocks: [
				{
					type: 'p',
					text: 'Durante uma prova ao vivo, Parar não encerra sua prova. Ele pausa a gravação e mostra **Prova pausada**. O relógio da prova continua correndo.',
				},
				{
					type: 'list',
					items: [
						'**Retomar prova** continua a gravação.',
						'**Finalizar prova** encerra sua prova agora. Se você cobriu pelo menos 90% do percurso, é uma chegada manual naquele momento.',
						'Abaixo de 90%, o botão mostra **Finalizar como DNF**, e finalizar registra um DNF.',
					],
				},
				{
					type: 'p',
					text: 'Em um relógio Wear OS, a tela de pausa oferece “Vai” para retomar, e você segura **Fim** para finalizar.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Finalizar antes de 90% do percurso registra um DNF. Se você só parou para amarrar o cadarço, escolha **Retomar prova**.',
				},
			],
		},
		{
			heading: 'Sem sinal na chegada',
			blocks: [
				{
					type: 'p',
					text: 'As linhas de chegada costumam ter sinal fraco. Seu celular e seu relógio Wear OS salvam o resultado primeiro e o enviam assim que se reconectam, então ele não se perde. Ele precisa chegar até nós em até 24 horas depois que o organizador encerrar a prova. Não saia da sua conta no app antes de o resultado ser enviado.',
				},
			],
		},
		{
			heading: 'Tempo bruto, tempo líquido e largadas atrasadas',
			blocks: [
				{
					type: 'list',
					items: [
						'O **Tempo bruto** vai do momento em que o organizador deu o GO até a sua chegada. É o tempo usado na sua classificação.',
						'O **Tempo líquido** vai do seu cruzamento da linha de largada até a sua chegada. Se nenhum cruzamento da linha de largada foi detectado, ele conta a partir de quando você pressionou Iniciar, ou a partir do GO se você pressionou Iniciar antes. Ele nunca é maior que o seu tempo bruto.',
						'Se você largar mais de 5 minutos depois do GO, ou se sua primeira posição estiver a mais de 200 m da largada do percurso, o app do celular mostra um aviso de largada tardia e um relógio Wear OS mantém **Largada tardia** abaixo do relógio da prova. Seu tempo bruto continua contando a partir do GO, então uma largada tardia o deixa maior que o seu tempo líquido.',
					],
				},
				{
					type: 'p',
					text: 'Mais sobre como ler a classificação em [[guide:race-results-explained|Como funcionam os resultados de prova]].',
				},
			],
		},
		{
			heading: 'Se o organizador encerrar a prova antes',
			blocks: [
				{
					type: 'p',
					text: 'Se o organizador encerrar a prova antes da sua chegada, seu celular avisa e seu relógio mostra “Corrida encerrada”. Sua corrida continua sendo gravada como uma corrida normal, mas seu dispositivo não envia resultado de prova. Se você já tinha enviado uma posição ao vivo, a prova marca você como DNF.',
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
