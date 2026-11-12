import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'live-tracking-and-safety',
	title: 'Acompanhamento em direto e contactos de segurança',
	summary: 'Deixe alguém seguir a sua corrida em direto e faça com que contactos de confiança recebam um e-mail quando termina, deixa de dar sinal ou não regressa a tempo.',
	sections: [
		{
			heading: 'Partilhar um link em direto',
			blocks: [
				{
					type: 'steps',
					items: [
						'Inicie sessão na app do telemóvel. Um link em direto só funciona para quem corre com sessão iniciada.',
						'No ecrã de corrida, antes de começar, toque em **Partilhar link em direto** e envie-o com qualquer app do seu telemóvel.',
						'Toque em **INICIAR**. O link fica ativo quando a corrida começa.',
					],
				},
				{
					type: 'p',
					text: 'Quem tiver o link pode abri-lo num navegador e ver a sua posição e as suas estatísticas, sem precisar de conta. As zonas de privacidade continuam a aplicar-se ao mapa em direto.',
				},
				{
					type: 'p',
					text: 'Durante a partilha, aparece um selo **Em direto** no ecrã de gravação. Toque nele para **Partilhar link novamente**, **Parar partilha** ou definir uma hora em **Se não regressar até…**.',
				},
				{
					type: 'p',
					text: 'Quando a corrida termina, o link deixa de ser atualizado. Se as suas corridas normalmente não são públicas, é-lhe perguntado se quer **Manter pública** a corrida guardada para quem tem o link; caso contrário, volta à privacidade habitual das suas corridas.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Para partilhar todas as corridas sem ter de se lembrar, ative **Partilha em direto automática** em **Contactos de segurança**, no separador **Tu**. Aplica-se apenas a esse telemóvel. A descrição indica quem pode acompanhar: qualquer pessoa com o link ou apenas os seus contactos de segurança (veja a última secção).',
				},
				{
					type: 'illustration',
					id: 'live-tracking-and-safety',
					alt: 'O telemóvel de um corredor envia a sua posição em direto a duas pessoas, que a acompanham cada uma no seu próprio ecrã.',
				},
			],
		},
		{
			heading: 'Adicionar contactos de segurança',
			blocks: [
				{
					type: 'p',
					text: 'Um contacto de segurança é alguém em quem confia, como o seu companheiro, um amigo ou um familiar. Sempre que termina uma corrida, mesmo que seja privada, essa pessoa recebe um e-mail e fica a saber que regressou.',
				},
				{
					type: 'steps',
					items: [
						'Na web, abra [[route:/settings/safety|Segurança]] nas Definições ou, na app do telemóvel, abra **Contactos de segurança** no separador **Tu**.',
						'Introduza o **E-mail do contacto**. Também pode adicionar um **Telemóvel para SMS (opcional)** em formato internacional, como +447700900123.',
						'Selecione **Adicionar contacto**. A pessoa recebe um e-mail a pedir-lhe que confirme.',
						'O estado mostra **Pendente — a aguardar a confirmação** até a pessoa aceitar e, depois, **Confirmado**. Só os contactos confirmados são alertados.',
					],
				},
				{
					type: 'p',
					text: 'Se alguém o adicionar como contacto, o pedido aparece em **Pedidos para si**, onde pode **Confirmar** ou **Recusar**. Mais tarde, em **É contacto de segurança**, pode alterar a forma como é alertado ou **Sair**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Os alertas por e-mail são sempre enviados. As mensagens de texto também exigem que o contacto concorde quando confirma, e o envio de SMS ainda não está ativo em todo o lado, por isso não confie apenas no SMS.',
				},
			],
		},
		{
			heading: 'Alertas quando algo parece errado',
			blocks: [
				{
					type: 'p',
					text: 'Estes alertas só abrangem corridas com a partilha em direto ativa, porque é o link em direto que nos diz onde está. Cada contacto recebe no máximo um alerta por corrida.',
				},
				{
					type: 'list',
					items: [
						'**Alerta de atraso**: escolha um tempo em **Avisar os contactos após silêncio de** na web, ou em **Avisar após silêncio de** na app. Se a sua corrida em direto não enviar nada durante esse tempo, os seus contactos confirmados recebem por e-mail o seu link em direto. Fica **Desativado** até escolher um tempo.',
						'**Se não regressar até…**: durante uma corrida com partilha em direto, toque no selo **Em direto** e escolha quando espera terminar. Se a corrida ainda estiver a decorrer nessa altura, os seus contactos são alertados. A hora fica guardada no nosso servidor, por isso continua a contar mesmo que o telemóvel fique sem bateria. Também a pode definir na sua própria página em direto, na web.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Ficar sem rede no telemóvel tem o mesmo aspeto que deixar de dar sinal, e uma corrida que termina sem rede pode ainda disparar um alerta até ser carregada. O e-mail diz aos seus contactos que a falta de rede é uma causa possível.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Um alerta automático para os seus contactos quando sai da rota planeada já está construído, mas ainda não está ativo. Até lá, a definição **Alerta de saída de rota** continua oculta.',
				},
			],
		},
		{
			heading: 'Avisos de saída de rota durante a corrida',
			blocks: [
				{
					type: 'p',
					text: 'Se seguir uma rota guardada, o ecrã de corrida avisa-o quando se afasta dela, mostrando a que distância está, e pode dizê-lo em voz alta se as indicações de áudio estiverem ativas. Este aviso é para si; não contacta ninguém.',
				},
			],
		},
		{
			heading: 'Partilhar apenas com os seus contactos de segurança',
			blocks: [
				{
					type: 'p',
					text: 'Onde a partilha apenas com contactos de segurança estiver ativada, a descrição de **Partilha em direto automática** diz que a partilha nunca é pública. A corrida em curso fica então oculta para todos exceto para si, até ser disparado um alerta de atraso ou de saída de rota. Só nessa altura cada contacto confirmado recebe o seu próprio link, no e-mail ou SMS de alerta.',
				},
				{
					type: 'list',
					items: [
						'A **Partilha em direto automática** ativa-se sozinha assim que definir um alerta de atraso, a não ser que a tenha desativado.',
						'Tocar em **Partilhar link em direto** continua a criar um link público, como descrito acima.',
						'O link de um contacto mostra **Apenas contactos de segurança**. É só para essa pessoa, por isso peça-lhe que não o reencaminhe. Deixa de funcionar quando a corrida termina, quando para de partilhar ou ao fim de 48 horas.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'A partilha apenas com contactos de segurança pode ainda não estar ativada. Até lá, uma partilha em direto automática pode ser vista por qualquer pessoa com o link.',
				},
			],
		},
	],
	sources: {
		title: 'cee4d0a20867ed19',
		summary: '45984309810e4f6b',
		's0.heading': 'dc5c5a630221dbbc',
		's0.b0.i0': 'f62182995094fa0a',
		's0.b0.i1': '5df8617dc302468a',
		's0.b0.i2': 'fd23a78c3f8edbbd',
		's0.b1': 'f45b4fcfccc4fb7e',
		's0.b2': '7845c9dd61f6fcbd',
		's0.b3': '21b6940abd1d8d09',
		's0.b4': '5ac2ca8e766db07b',
		's0.b5': 'eb575f135ac66d66',
		's1.heading': '7fe0f3d3bca83ca6',
		's1.b0': '8983069471135762',
		's1.b1.i0': '6675420e0916edbb',
		's1.b1.i1': '8ad53d18b45a91df',
		's1.b1.i2': '921f48df34ed7a60',
		's1.b1.i3': 'fb0e10c56d0013a1',
		's1.b2': 'd5654527a9969a6c',
		's1.b3': '38a6734637422840',
		's2.heading': '6494ef66d8a744ee',
		's2.b0': '3076b2df5cf96aca',
		's2.b1.i0': 'd1a279384aa709ce',
		's2.b1.i1': '43b13b285ccc1278',
		's2.b2': '968742a451f6aa8a',
		's2.b3': '0694224872716044',
		's3.heading': '4799e1fbd28720f2',
		's3.b0': '2557edbaef77cc2c',
		's4.heading': '77cc43259f01d7cd',
		's4.b0': '5486560d83005e0c',
		's4.b1.i0': '263589d27a310489',
		's4.b1.i1': '5d8ab8e5ec1ecd1c',
		's4.b1.i2': 'de89e5227402c8e0',
		's4.b2': 'd3861ef7e8756240',
	},
};
