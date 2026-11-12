import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'live-tracking-and-safety',
	title: 'Rastreamento ao vivo e contatos de segurança',
	summary: 'Deixe alguém acompanhar sua corrida ao vivo e faça com que contatos de confiança recebam um e-mail quando você terminar, ficar em silêncio ou não voltar no horário.',
	sections: [
		{
			heading: 'Compartilhar um link ao vivo',
			blocks: [
				{
					type: 'steps',
					items: [
						'Entre na sua conta no app do celular. O link ao vivo só funciona para um corredor conectado.',
						'Na tela de corrida, antes de começar, toque em **Compartilhar link ao vivo** e envie-o por qualquer app do seu celular.',
						'Toque em **INICIAR**. O link fica ao vivo quando a corrida começa.',
					],
				},
				{
					type: 'p',
					text: 'Quem tiver o link pode abri-lo em um navegador e ver sua posição e suas estatísticas, sem precisar de conta. As zonas de privacidade continuam valendo no mapa ao vivo.',
				},
				{
					type: 'p',
					text: 'Durante o compartilhamento, um selo **Ao vivo** aparece na tela de gravação. Toque nele para **Compartilhar link novamente**, **Parar de compartilhar** ou definir um horário em **Sem retorno até…**.',
				},
				{
					type: 'p',
					text: 'Quando a corrida termina, o link para de ser atualizado. Se suas corridas normalmente não são públicas, o app pergunta se você quer **Manter pública** a corrida salva para quem tem o link; caso contrário, ela volta para a privacidade de sempre das suas corridas.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Para compartilhar todas as corridas sem precisar lembrar, ative **Compartilhamento ao vivo automático** em **Contatos de segurança**, na aba **Você**. Vale só para aquele celular. A descrição diz quem pode acompanhar: qualquer pessoa com o link ou só os seus contatos de segurança (veja a última seção).',
				},
				{
					type: 'illustration',
					id: 'live-tracking-and-safety',
					alt: 'O celular de um corredor envia sua posição ao vivo para duas pessoas, que a acompanham cada uma na própria tela.',
				},
			],
		},
		{
			heading: 'Adicionar contatos de segurança',
			blocks: [
				{
					type: 'p',
					text: 'Um contato de segurança é alguém em quem você confia, como um parceiro, um amigo ou um familiar. Essa pessoa recebe um e-mail quando você termina uma corrida, mesmo uma corrida privada, para saber que você voltou.',
				},
				{
					type: 'steps',
					items: [
						'Na web, abra [[route:/settings/safety|Segurança]] em Configurações; no app do celular, abra **Contatos de segurança** na aba **Você**.',
						'Digite o **E-mail do contato**. Você também pode adicionar um **Telefone para SMS (opcional)** no formato internacional, como +447700900123.',
						'Selecione **Adicionar contato**. A pessoa recebe um e-mail pedindo que confirme.',
						'O status do contato mostra **Pendente — aguardando a confirmação** até que ele aceite e, depois, **Confirmado**. Só os contatos confirmados recebem alertas.',
					],
				},
				{
					type: 'p',
					text: 'Se alguém adicionar você como contato, o pedido aparece em **Pedidos para você**, onde você pode **Confirmar** ou **Recusar**. Depois, em **Você é contato de segurança**, você pode mudar como é avisado ou **Sair**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Os alertas por e-mail são sempre enviados. As mensagens de texto também exigem que o contato concorde ao confirmar, e o envio de SMS ainda não está ativado em todos os lugares, então não dependa só do SMS.',
				},
			],
		},
		{
			heading: 'Alertas quando algo parece errado',
			blocks: [
				{
					type: 'p',
					text: 'Esses alertas só cobrem corridas com o compartilhamento ao vivo ativado, porque é o link ao vivo que nos diz onde você está. Cada contato recebe no máximo um alerta por corrida.',
				},
				{
					type: 'list',
					items: [
						'**Alerta de atraso**: escolha um tempo em **Avisar os contatos após silêncio de** na web, ou **Avisar após silêncio de** no app. Se sua corrida ao vivo não enviar nada por esse tempo, seus contatos confirmados recebem por e-mail o seu link ao vivo. Fica **Desativado** até você escolher um tempo.',
						'**Sem retorno até…**: durante uma corrida compartilhada ao vivo, toque no selo **Ao vivo** e escolha quando você espera terminar. Se a corrida ainda estiver em andamento nesse horário, seus contatos recebem um alerta. O horário fica guardado no nosso servidor, então continua valendo mesmo se a bateria do seu celular acabar. Você também pode defini-lo pela sua própria página ao vivo na web.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Perder o sinal do celular parece igual a ficar em silêncio, e uma corrida que termina sem sinal ainda pode disparar um alerta até ser enviada. O e-mail avisa seus contatos que a perda de sinal é uma causa possível.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Um alerta automático para seus contatos quando você sai da rota planejada já foi construído, mas ainda não está ativado. Até que esteja, a configuração **Alerta de saída de rota** fica oculta.',
				},
			],
		},
		{
			heading: 'Avisos de saída de rota durante a corrida',
			blocks: [
				{
					type: 'p',
					text: 'Se você seguir uma rota salva, a tela de corrida avisa quando você se afasta dela, mostrando a que distância você está, e pode dizer isso em voz alta se os avisos de áudio estiverem ativados. Esse aviso é para você; ele não entra em contato com ninguém.',
				},
			],
		},
		{
			heading: 'Compartilhar só com seus contatos de segurança',
			blocks: [
				{
					type: 'p',
					text: 'Onde o compartilhamento só com contatos de segurança estiver ativado, a descrição de **Compartilhamento ao vivo automático** diz que ele nunca é público. A corrida em andamento fica então oculta para todos, menos você, até que um alerta de atraso ou de saída de rota seja disparado. Só então cada contato confirmado recebe o próprio link, no e-mail ou SMS de alerta.',
				},
				{
					type: 'list',
					items: [
						'O **Compartilhamento ao vivo automático** é ativado sozinho assim que você define um alerta de atraso, a menos que você mesmo o tenha desativado.',
						'Tocar em **Compartilhar link ao vivo** continua criando um link público, como descrito acima.',
						'O link de um contato mostra **Somente contatos de segurança**. Ele é só para essa pessoa, então peça que ela não o encaminhe. Ele para de funcionar quando a corrida termina, quando você para de compartilhar ou depois de 48 horas.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'O compartilhamento só com contatos de segurança pode ainda não estar ativado. Até lá, um compartilhamento ao vivo automático pode ser visto por qualquer pessoa com o link.',
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
