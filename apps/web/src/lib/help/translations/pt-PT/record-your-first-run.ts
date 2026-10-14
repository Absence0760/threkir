import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'record-your-first-run',
	title: 'Gravar a sua primeira corrida',
	summary: 'Inicie uma corrida no telemóvel, pause-a e pare-a em segurança, obtenha um bom sinal de GPS e veja o que fica guardado no fim.',
	sections: [
		{
			heading: 'Começar a gravar',
			blocks: [
				{
					type: 'p',
					text: 'As corridas são gravadas na app do telemóvel ou num relógio. A aplicação web mostra as suas corridas, mas não consegue gravar nenhuma.',
				},
				{
					type: 'steps',
					items: [
						'Toque no botão grande no meio da barra inferior. Diz **Correr**, ou **Registar** se tiver ativado o ginásio ou a nutrição; nesse caso, escolha **Registar corrida**.',
						'Toque em **INICIAR**. Da primeira vez, o telemóvel pede acesso à localização: permita-o, caso contrário a corrida grava apenas o tempo, sem distância nem mapa.',
						'Uma contagem decrescente de três segundos decorre enquanto o GPS aquece e, depois, o relógio começa a contar.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'No Android, escolha **Permitir sempre** para a localização. Com acesso apenas enquanto a app está aberta, a distância que percorre com o ecrã desligado não é contada, embora o relógio continue a contar.',
				},
				{
					type: 'illustration',
					id: 'record-your-first-run',
					alt: 'Um telemóvel com um grande botão redondo para iniciar, a captar o sinal GPS de um satélite no céu.',
				},
			],
		},
		{
			heading: 'Pausar e parar',
			blocks: [
				{
					type: 'p',
					text: 'Não há pausa automática: o relógio conta até o pausar. Use o botão de pausa para uma paragem que quer deixar fora do seu tempo, e o botão de retomar para continuar.',
				},
				{
					type: 'p',
					text: 'Ficar parado num cruzamento sem pausar não faz mal. Depois da corrida, o tempo **Em movimento** deixa de fora os troços em que esteve parado, e o seu ritmo é calculado a partir do tempo em movimento.',
				},
				{
					type: 'steps',
					items: [
						'Para terminar, mantenha premido o botão de parar. A indicação diz **Mantenha premido para parar**, para que um toque acidental no bolso não termine a corrida.',
						'O resumo **Corrida concluída** mostra a distância, o **Tempo**, o tempo **Em movimento**, o ritmo e quaisquer outras estatísticas que o telemóvel tenha medido.',
						'Toque em **Concluído** para voltar ao ecrã inicial.',
					],
				},
			],
		},
		{
			heading: 'Obter um bom sinal de GPS',
			blocks: [
				{
					type: 'list',
					items: [
						'Comece ao ar livre, longe de prédios altos e de copas de árvores densas, para que a contagem decrescente tenha uma vista desimpedida do céu.',
						'Se vir **Sinal de GPS perdido — vá para um local aberto**, continue: o relógio continua a contar e a distância volta a ser contada quando o sinal regressa.',
						'**GPS fraco — distância pausada** significa que a sua posição é demasiado incerta para contar. A distância retoma assim que o sinal melhora.',
						'Mantenha os serviços de localização ativos e a poupança de bateria desativada para a app, para que o telemóvel não pare a gravação em segundo plano.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Se a app fechar a meio da corrida, abra-a de novo: é-lhe perguntado **Retomar a sua corrida?** e pode retomá-la, terminá-la já ou descartá-la.',
				},
			],
		},
		{
			heading: 'O que fica guardado',
			blocks: [
				{
					type: 'p',
					text: 'Quando para, a corrida é guardada primeiro no telemóvel e depois carregada para a sua conta. O resumo mostra **Sincronizada** quando já está em segurança na nuvem, ou **Guardada offline.** se não tiver sessão iniciada. Uma corrida que não foi possível carregar fica no telemóvel e volta a ser tentada mais tarde.',
				},
				{
					type: 'list',
					items: [
						'Distância, tempo decorrido, tempo em movimento e ritmo.',
						'O seu trajeto GPS, que desenha o mapa e os parciais.',
						'Elevação, passos e frequência cardíaca, se tiver emparelhado uma cinta de frequência cardíaca.',
					],
				},
				{
					type: 'p',
					text: 'Quem pode ver a corrida segue a sua definição **Privacidade predefinida das corridas**, que pode alterar depois para qualquer corrida individual. Para esconder onde vive, configure [[guide:privacy-zones|zonas de privacidade]] antes de partilhar o que quer que seja.',
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
