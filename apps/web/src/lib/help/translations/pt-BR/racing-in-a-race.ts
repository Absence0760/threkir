import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'racing-in-a-race',
	title: 'Correr uma prova ao vivo',
	summary: 'Inscreva-se, escolha seu percurso, comece a gravar na largada ou depois do GO e deixe seu celular ou relógio cronometrar você na linha de chegada.',
	sections: [
		{
			heading: 'Quais dispositivos funcionam em provas',
			blocks: [
				{
					type: 'list',
					items: [
						'App para Android: suporte completo. Mostra o banner da prova, envia sua posição ao vivo e registra sua chegada automaticamente.',
						'App para iPhone: roda o mesmo código do Android, mas ainda não foi testado em um iPhone em uma prova real.',
						'Relógio Wear OS: suporte completo no pulso, incluindo a chegada automática. Você ainda se inscreve e escolhe seu percurso na web ou no celular.',
						'Apple Watch: apenas suporte inicial. Mostra o banner da prova, envia sua posição e informa seu tempo pelo iPhone, mas não tem chegada automática e ainda não foi comprovado em uma prova real. Leve o celular como reserva.',
						'Web: use para se inscrever, escolher um percurso e ver os resultados. Um navegador não consegue gravar uma corrida.',
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
			heading: 'Prova pronta e Prova AO VIVO',
			blocks: [
				{
					type: 'p',
					text: 'Quando o organizador prepara a prova, a aba Corrida do app do celular mostra **Prova pronta** com “aguardando a largada”. O relógio Wear OS mostra “RACE ARMED” acima do botão Start. Quando o organizador dá o GO, isso muda para **Prova AO VIVO** (“RACE LIVE” no relógio), com o tempo decorrido e “toque em Iniciar”.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Seu celular ou relógio não começa a gravar sozinho: pressione Iniciar você mesmo. Você pode começar na linha de largada enquanto a prova mostra **Prova pronta**, ou quando vir **Prova AO VIVO**. Uma gravação iniciada antes entra na prova no GO, no celular e no relógio Wear OS, e seu tempo líquido passa a contar a partir do GO, e não de quando você pressionou Iniciar.',
				},
				{
					type: 'p',
					text: 'O app do celular verifica as provas em que você disse **Eu vou** e que começam em até um dia. Se o banner demorar a aparecer, mantenha o app aberto na aba Corrida por um minuto.',
				},
			],
		},
		{
			heading: 'Chegada automática',
			blocks: [
				{
					type: 'p',
					text: 'Você não precisa pressionar nada na chegada. Seu celular ou relógio Wear OS registra sua chegada quando as duas condições abaixo são verdadeiras:',
				},
				{
					type: 'list',
					items: [
						'você está a até 30 m da linha de chegada, e',
						'você cobriu pelo menos 90% da distância do seu percurso.',
					],
				},
				{
					type: 'p',
					text: 'Seu tempo é registrado no momento em que você esteve mais perto da chegada, não no primeiro momento em que ficou a menos de 30 m. A regra dos 90% evita que um percurso em circuito, que começa onde termina, registre sua chegada no primeiro segundo. O celular mostra “Chegada!” com o seu tempo bruto, e a gravação para.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se o seu percurso não tem rota nem distância, não há chegada automática. Use Parar e depois **Finalizar prova** quando cruzar a linha.',
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
						'O **Tempo líquido** vai de quando você pressionou Iniciar até a sua chegada, incluindo as pausas. Se você pressionou Iniciar antes do GO, ele conta a partir do GO, então nunca é maior que o seu tempo bruto.',
						'Se você largar mais de 5 minutos depois do GO, ou se sua primeira posição estiver a mais de 200 m da largada do percurso, o app do celular mostra um aviso de largada atrasada. Seu tempo bruto continua contando a partir do GO, então uma largada atrasada o deixa maior que o seu tempo líquido.',
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
					text: 'Se o organizador encerrar a prova antes da sua chegada, seu celular avisa e seu relógio mostra “Race ended”. Sua corrida continua sendo gravada como uma corrida normal, mas seu dispositivo não envia resultado de prova. Se você já tinha enviado uma posição ao vivo, a prova marca você como DNF.',
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
