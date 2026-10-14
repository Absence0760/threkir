import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'using-help',
	title: 'Encontrar ajuda na app',
	summary: 'Onde ficam os guias de ajuda, como pesquisá-los e como passar de um ecrã para o guia que o explica.',
	sections: [
		{
			heading: 'Abrir a ajuda',
			blocks: [
				{
					type: 'steps',
					items: [
						'Selecione o seu nome no fundo da barra lateral. Numa janela estreita, a barra lateral reduz-se a ícones, por isso selecione antes o avatar redondo com a sua inicial.',
						'Escolha **Ajuda** no menu que se abre.',
					],
				},
				{
					type: 'p',
					text: 'A página de conteúdos lista todos os guias por tema. Os chips em **Mostrar guias para** restringem a lista aos guias escritos para si, como **Organizadores** ou **Espectadores**; **Todos** volta a mostrar tudo.',
				},
			],
		},
		{
			heading: 'Pesquisar nos guias',
			blocks: [
				{
					type: 'p',
					text: 'Escreva uma ou duas palavras em **Pesquisar nos guias** no topo de [[route:/help|Ajuda]] e prima **Pesquisar**. Os guias com as suas palavras no título aparecem primeiro, depois os que as mencionam no resumo e depois os restantes.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Maiúsculas e acentos não contam, por isso *cafe* encontra *Café*. Cada palavra que escrever tem de aparecer algures num guia para que este seja listado.',
				},
			],
		},
		{
			heading: 'Ajuda a partir do ecrã em que está',
			blocks: [
				{
					type: 'p',
					text: 'Um ecrã que tem um guia mostra uma ligação **Como funciona** junto ao título. Abre o guia desse ecrã; quando há vários guias sobre ele, abre uma pequena lista para escolher.',
				},
				{
					type: 'p',
					text: 'Alguns cartões e definições têm um pequeno botão redondo *i*. Explica a funcionalidade numa ou duas frases e, quando um guia vai mais longe, termina com **Ler o guia**.',
				},
			],
		},
		{
			heading: 'Ler um guia',
			blocks: [
				{
					type: 'list',
					items: [
						'Os distintivos por baixo do título indicam a que apps o guia se aplica e se precisa de algo antes, como o Pro ou uma função de administrador de clube.',
						'**Nesta página** lista as secções de um guia mais longo e salta para a que escolher.',
						'**Guias relacionados**, no fim, aponta para o que provavelmente vai precisar a seguir.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Os guias são mostrados no idioma definido na app. Um guia que ainda não foi traduzido para esse idioma é mostrado em inglês, com uma nota no topo a indicá-lo.',
				},
			],
		},
	],
	sources: {
		title: '24b24e04778319f0',
		summary: 'a48673503416ac4b',
		's0.heading': '7a1c4fbaadb140c8',
		's0.b0.i0': '30e5295b4da5ba3c',
		's0.b0.i1': 'e71dfa25299f1bfd',
		's0.b1': 'cad6c1b6c1df821e',
		's1.heading': '04ea92e3c4004802',
		's1.b0': 'e2a5a0ec166b1e7e',
		's1.b1': '335fc384cdbd905d',
		's2.heading': '2c9250315085b9f5',
		's2.b0': '956cf1fffb9b9281',
		's2.b1': '77c2e5882892db56',
		's3.heading': 'e8cea7066700293f',
		's3.b0.i0': 'ba5bfc36d130445d',
		's3.b0.i1': '542a777c6fe5c9c7',
		's3.b0.i2': '71fa810fa8981b8e',
		's3.b1': 'e8aa5e2de0ab9bdb',
	},
};
