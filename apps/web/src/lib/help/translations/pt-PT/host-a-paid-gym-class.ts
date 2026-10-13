import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'host-a-paid-gym-class',
	title: 'Organizar uma aula paga de HIIT, força ou bootcamp',
	summary: 'Agende uma aula de ginásio recorrente com limite de vagas e preço por aula, partilhe o treino como rotina do clube e deixe os participantes registá-lo no seu próprio histórico.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'As aulas pagas ainda não estão disponíveis. Receber dinheiro exige a sua própria conta Stripe ligada ([[guide:get-paid-with-stripe|Receber pagamento pelos eventos que organiza]]) e a inscrição paga ativada pela plataforma. Até lá, o interruptor **Cobrar por este evento** fica desligado e pode continuar a dar a aula gratuitamente.',
				},
				{
					type: 'p',
					text: 'Tem de ser administrador ou organizador de eventos do clube. O preço, a capacidade e o calendário de repetição definem-se na web; a app do telemóvel pode criar uma aula, mas não tem campos para estes dados.',
				},
			],
		},
		{
			heading: 'Criar a aula',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o seu clube, vá ao separador **Eventos** e prima **Novo evento**.',
						'Em **Tipo de evento**, escolha **Aula**. O percurso, a distância, o ritmo e os resultados de prova ficam ocultos numa aula.',
						'Preencha a **Disciplina**, por exemplo “HIIT” ou “Bootcamp”, e um **Título** que as pessoas reconheçam no calendário.',
						'Defina a **Duração predefinida do treino** com a duração da aula em minutos. É isto que permite aos participantes registar a aula com um só toque depois.',
						'Defina a **Data**, a **Hora de início**, a **Duração** e o **Ponto de encontro**.',
						'Em **Repetição**, escolha **Semanal**, **A cada 2 semanas** ou **Mensal** e os dias. Só pode escolher isto ao criar o evento.',
						'Defina a **Capacidade** de acordo com os seus racks, bicicletas ou vagas.',
						'Ative **Cobrar por este evento** e depois defina o **Preço**, a **Moeda**, **Encerrar vendas (minutos antes do início)** e uma **Política de reembolso**. O preço e a moeda não podem ser alterados depois de o evento ser criado.',
						'Prima **Criar evento**.',
					],
				},
			],
		},
		{
			heading: 'Partilhar o treino com a sua aula',
			blocks: [
				{
					type: 'p',
					text: 'Uma aula ainda não pode ter uma rotina de ginásio associada diretamente. Em vez disso, publique a sua rotina no clube, onde os membros a podem copiar para as suas próprias rotinas e executá-la.',
				},
				{
					type: 'steps',
					items: [
						'Crie a rotina: consulte [[guide:build-a-gym-routine|Criar uma rotina de ginásio]].',
						'Abra a rotina e, em **Publicar num clube**, escolha o seu clube em **Escolha um clube…** e prima **Publicar**.',
						'Aparece no separador **Modelos** do clube, em **Modelos de rotina de ginásio**, marcada como **Modelo do clube**. Os membros premem **Adotar** para obter a sua própria cópia.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Os administradores do clube também podem ir diretamente ao separador **Modelos**, premir **Adicionar modelo** e escolher **Rotina de ginásio**. Fica guardada como modelo do clube num só passo.',
				},
			],
		},
		{
			heading: 'Os participantes registam a aula no seu histórico',
			blocks: [
				{
					type: 'p',
					text: 'Na página da aula, qualquer participante com sessão iniciada vê **Registar como treino**. Abre um registo de ginásio já com o nome da aula, que a pessoa pode ajustar com as suas próprias séries e pesos antes de guardar. Depois vê **Adicionado ao seu registo de ginásio**, e a aula conta no seu histórico de treino como qualquer outro treino. Funciona na web e na app do telemóvel.',
				},
				{
					type: 'p',
					text: 'Quem adotou a sua rotina pode, em vez disso, abri-la e premir **Iniciar rotina** para ser guiado série a série; essa sessão também fica guardada no seu registo de ginásio.',
				},
			],
		},
		{
			heading: 'Inscrição, o próprio dia e alterações',
			blocks: [
				{
					type: 'list',
					items: [
						'Os participantes inscrevem-se e pagam na web, veem **Está inscrito** e podem cancelar de acordo com a sua [[guide:refund-policies|política de reembolso]].',
						'Quando as vagas se esgotam, aparece **Esgotado** e a opção **Entrar na lista de espera**: consulte [[guide:waitlist-and-claim-window|Listas de espera e o prazo de 12 horas para garantir o lugar]].',
						'Marque quem compareceu: [[guide:take-attendance|Registar presenças]].',
						'Cancelar uma sessão reembolsa todos os que pagaram: [[guide:cancel-a-class|Cancelar uma aula]].',
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
