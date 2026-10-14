import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'record-your-first-run',
	title: 'Gravar sua primeira corrida',
	summary: 'Comece uma corrida no celular, pause e pare com segurança, consiga um bom sinal de GPS e veja o que é salvo depois.',
	sections: [
		{
			heading: 'Começar a gravar',
			blocks: [
				{
					type: 'p',
					text: 'As corridas são gravadas no app do celular ou em um relógio. O app web mostra suas corridas, mas não consegue gravar uma.',
				},
				{
					type: 'steps',
					items: [
						'Toque no botão grande no meio da barra inferior. Ele mostra **Correr**, ou **Registrar** se você ativou academia ou nutrição; nesse caso, escolha **Registrar corrida**.',
						'Toque em **INICIAR**. Na primeira vez, o celular pede acesso à localização: permita, senão a corrida grava só o tempo, sem distância nem mapa.',
						'Uma contagem regressiva de três segundos corre enquanto o GPS se prepara, e então o cronômetro começa.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'No Android, escolha **Permitir o tempo todo** para a localização. Com acesso só enquanto o app está aberto, a distância que você percorre com a tela desligada não é contada, embora o cronômetro continue correndo.',
				},
				{
					type: 'illustration',
					id: 'record-your-first-run',
					alt: 'Um celular com um grande botão redondo para iniciar, captando o sinal de GPS de um satélite no céu.',
				},
			],
		},
		{
			heading: 'Pausar e parar',
			blocks: [
				{
					type: 'p',
					text: 'Não há pausa automática: o cronômetro corre até você pausá-lo. Use o botão de pausa para uma parada que você quer deixar fora do seu tempo, e o botão de retomar para continuar.',
				},
				{
					type: 'p',
					text: 'Ficar parado em um cruzamento sem pausar não faz mal. Depois da corrida, o tempo **Em movimento** deixa de fora os trechos em que você estava parado, e o seu ritmo é calculado a partir do tempo em movimento.',
				},
				{
					type: 'steps',
					items: [
						'Para terminar, pressione e segure o botão de parar. A dica diz **Segure para parar**, para que um toque acidental no bolso não encerre a corrida.',
						'O resumo **Corrida concluída** mostra sua distância, o **Tempo**, o tempo **Em movimento**, o ritmo e as outras estatísticas que o seu celular mediu.',
						'Toque em **Concluído** para voltar à tela inicial.',
					],
				},
			],
		},
		{
			heading: 'Como conseguir um bom sinal de GPS',
			blocks: [
				{
					type: 'list',
					items: [
						'Comece ao ar livre, longe de prédios altos e de árvores densas, para que a contagem regressiva tenha uma visão livre do céu.',
						'Se você vir **Sinal de GPS perdido — vá para um local aberto**, continue: o cronômetro segue correndo e a distância volta a ser contada quando o sinal retornar.',
						'**GPS fraco — distância pausada** significa que sua posição está incerta demais para ser contada. A distância volta assim que o sinal melhorar.',
						'Mantenha os serviços de localização ativados e a economia de bateria desativada para o app, para que o celular não interrompa a gravação em segundo plano.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se o app fechar no meio da corrida, abra-o de novo: aparece a pergunta **Retomar sua corrida?** e você pode retomar, finalizar agora ou descartar a corrida.',
				},
			],
		},
		{
			heading: 'O que é salvo',
			blocks: [
				{
					type: 'p',
					text: 'Quando você para, a corrida é salva primeiro no seu celular e depois enviada para a sua conta. O resumo mostra **Sincronizada** quando ela está segura na nuvem, ou **Salva offline.** se você não estiver conectado à sua conta. Uma corrida que não pôde ser enviada fica no celular e é enviada de novo mais tarde.',
				},
				{
					type: 'list',
					items: [
						'Distância, tempo total, tempo em movimento e ritmo.',
						'Seu trajeto de GPS, que desenha o mapa e as parciais.',
						'Elevação, passos e frequência cardíaca, se você pareou uma cinta cardíaca.',
					],
				},
				{
					type: 'p',
					text: 'Quem pode ver a corrida segue a sua configuração **Privacidade padrão das corridas**, que você pode mudar depois para qualquer corrida específica. Para esconder onde você mora, configure [[guide:privacy-zones|zonas de privacidade]] antes de compartilhar qualquer coisa.',
				},
			],
		},
	],
	sources: {
		title: '70047f50b01f1af6',
		summary: 'dc170443668c395f',
		's0.heading': '30756af0134e4bf1',
		's0.b0': '6dc07a2b5e601838',
		's0.b1.i0': 'a7632a8cd2567c2c',
		's0.b1.i1': '68b860679cd99712',
		's0.b1.i2': 'a406181fe0c90b54',
		's0.b2': 'b93825fb9981ec39',
		's1.heading': '7c0f775fc550ae67',
		's1.b0': '7cdb0afab0e6c855',
		's1.b1': '1514c09a3d983d9e',
		's1.b2.i0': '2c86f71499d052af',
		's1.b2.i1': 'a2b9c26b2835d1ac',
		's1.b2.i2': 'c28a30ef42432d2f',
		's2.heading': 'cb9aedf1a5764367',
		's2.b0.i0': '35ba6295ed45225d',
		's2.b0.i1': '44f804dddcf3049e',
		's2.b0.i2': 'b8c55726529e022b',
		's2.b0.i3': '514cfcccb3fc6f5e',
		's2.b1': '2f0d094e06e813c3',
		's3.heading': 'f075ba7c6636fa8a',
		's3.b0': 'ef5a53403410399c',
		's3.b1.i0': 'ec005f0ead60e9e0',
		's3.b1.i1': 'e0fd699761f32367',
		's3.b1.i2': '1d33b3ee8d0be1b8',
		's3.b2': 'a8054fd15c256c3c',
		's0.b3': '21307fc19189cc42',
	},
};
