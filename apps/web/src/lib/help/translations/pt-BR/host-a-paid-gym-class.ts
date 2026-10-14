import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'host-a-paid-gym-class',
	title: 'Oferecer uma aula paga de HIIT, força ou bootcamp',
	summary: 'Agende uma aula de academia recorrente com limite de vagas e preço avulso, compartilhe o treino como rotina do clube e deixe os participantes registrarem a aula no próprio histórico.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'As aulas pagas ainda não estão disponíveis. Receber pagamentos exige a sua própria conta Stripe conectada ([[guide:get-paid-with-stripe|Receber pelos eventos que você organiza]]) e o sistema de pagamentos da plataforma ativado. Até lá, a opção **Cobrar por este evento** fica desligada e você ainda pode dar a aula de graça.',
				},
				{
					type: 'p',
					text: 'Você precisa ser administrador ou organizador de eventos do clube. Preço, capacidade e a programação de repetição são definidos na web; o app para celular pode criar uma aula, mas não tem campos para eles.',
				},
			],
		},
		{
			heading: 'Criar a aula',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o seu clube, vá até a aba **Eventos** e clique em **Novo evento**.',
						'Em **Tipo de evento**, escolha **Aula**. Rota, distância, ritmo e resultados de prova ficam ocultos em uma aula.',
						'Preencha a **Modalidade**, por exemplo “HIIT” ou “Bootcamp”, e um **Título** que as pessoas reconheçam no calendário.',
						'Defina a **Duração padrão do treino** como a duração da aula em minutos. É isso que permite aos participantes registrar a aula com um toque depois.',
						'Defina a **Data**, o **Horário de início**, a **Duração** e o **Ponto de encontro**.',
						'Em **Repetição**, escolha **Semanal**, **A cada 2 semanas** ou **Mensal** e os dias. Você só pode escolher isso enquanto cria o evento.',
						'Defina a **Capacidade** de acordo com os seus racks, bikes ou vagas.',
						'Ative **Cobrar por este evento** e defina o **Preço**, a **Moeda**, **Encerrar vendas (minutos antes do início)** e uma **Política de reembolso**. O preço e a moeda não podem ser alterados depois que o evento é criado.',
						'Clique em **Criar evento**.',
					],
				},
			],
		},
		{
			heading: 'Compartilhar o treino com a turma',
			blocks: [
				{
					type: 'p',
					text: 'Uma aula ainda não pode trazer uma rotina de academia diretamente. Em vez disso, publique a sua rotina no clube, onde os membros podem copiá-la para as próprias rotinas e executá-la.',
				},
				{
					type: 'steps',
					items: [
						'Monte a rotina: veja [[guide:build-a-gym-routine|Montar uma rotina de academia]].',
						'Abra a rotina e, em **Publicar em um clube**, escolha o seu clube em **Escolha um clube…** e clique em **Publicar**.',
						'Ela aparece na aba **Modelos** do clube, em **Modelos de rotina de academia**, marcada como **Modelo do clube**. Os membros clicam em **Adotar** para ter a própria cópia.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Os administradores do clube também podem ir direto à aba **Modelos**, clicar em **Adicionar modelo** e escolher **Rotina de academia**. Ela é salva como modelo do clube em uma única etapa.',
				},
			],
		},
		{
			heading: 'Os participantes registram a aula no próprio histórico',
			blocks: [
				{
					type: 'p',
					text: 'Na página da aula, qualquer participante conectado vê **Registrar como treino**. Isso abre um registro de academia já com o nome da aula, que a pessoa pode ajustar com as próprias séries e cargas antes de salvar. Em seguida ela vê **Adicionado ao seu registro de academia**, e a aula conta no histórico de treinos como qualquer outro treino. Isso funciona na web e no app para celular.',
				},
				{
					type: 'p',
					text: 'Quem adotou a sua rotina pode, em vez disso, abri-la e clicar em **Iniciar rotina** para ser guiado série por série; essa sessão também é salva no registro de academia da pessoa.',
				},
			],
		},
		{
			heading: 'Inscrições, o dia da aula e mudanças',
			blocks: [
				{
					type: 'list',
					items: [
						'Os participantes se inscrevem e pagam na web, veem **Você está inscrito** e podem cancelar de acordo com a sua [[guide:refund-policies|política de reembolso]].',
						'Quando as vagas acabam, aparece **Esgotado** com a opção **Entrar na lista de espera**: veja [[guide:waitlist-and-claim-window|Listas de espera e o prazo de 12 horas para garantir a vaga]].',
						'Marque quem compareceu: [[guide:take-attendance|Registrar a presença]].',
						'Cancelar uma sessão reembolsa todos que pagaram: [[guide:cancel-a-class|Cancelar uma aula]].',
					],
				},
			],
		},
	],
	sources: {
		title: '821d1cdaad9c7f76',
		summary: 'fe033ea704336c87',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '201303c3b4fb7856',
		's0.b1': 'cda7868c50d0cb5f',
		's1.heading': '2be2beb0fdaf15d0',
		's1.b0.i0': '7305ee21de6e7b5b',
		's1.b0.i1': '3c9d0e87dfbeb2b0',
		's1.b0.i2': 'f5ba5f09a6974c79',
		's1.b0.i3': '33a8a722caa47142',
		's1.b0.i4': '102511520e8a1371',
		's1.b0.i5': 'efd088144f85d66a',
		's1.b0.i6': 'd8ec205082050572',
		's1.b0.i7': '5a77ffc2b4ed6f03',
		's1.b0.i8': '854dff74efad02f9',
		's2.heading': 'bbcfb1ff6677d7c4',
		's2.b0': 'e950a3414f06b735',
		's2.b1.i0': 'dfaa37a59a8694bd',
		's2.b1.i1': 'e4888330a1cf50da',
		's2.b1.i2': '8583726358642cc9',
		's2.b2': '2399946b61bf3531',
		's3.heading': 'bde153fbfeb20de5',
		's3.b0': '073d6ee2cb1c9925',
		's3.b1': 'd33452cd85ac8ba2',
		's4.heading': '2f15ae20fe8166de',
		's4.b0.i0': '08b55370b0377e69',
		's4.b0.i1': 'd916d4671efc3512',
		's4.b0.i2': '53cda3f1ada8ad06',
		's4.b0.i3': 'd8fbf8a81896cecd',
	},
};
