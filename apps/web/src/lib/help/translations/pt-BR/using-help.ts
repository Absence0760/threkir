import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'using-help',
	title: 'Como encontrar ajuda no app',
	summary: 'Onde ficam os guias de ajuda, como pesquisar neles e como ir de uma tela direto para o guia que a explica.',
	sections: [
		{
			heading: 'Como abrir a ajuda',
			blocks: [
				{
					type: 'steps',
					items: [
						'Selecione o seu nome na parte de baixo da barra lateral. Em uma janela estreita, a barra lateral encolhe para ícones; nesse caso, selecione o avatar redondo com a sua inicial.',
						'Escolha **Ajuda** no menu que se abre.',
					],
				},
				{
					type: 'p',
					text: 'A página de conteúdo lista todos os guias por assunto. Os chips em **Mostrar guias para** restringem a lista aos guias escritos para você, como **Organizadores** ou **Espectadores**; **Todos** mostra tudo de novo.',
				},
			],
		},
		{
			heading: 'Como pesquisar nos guias',
			blocks: [
				{
					type: 'p',
					text: 'Digite uma ou duas palavras em **Pesquisar nos guias**, no topo de [[route:/help|Ajuda]], e clique em **Pesquisar**. Os guias com as suas palavras no título aparecem primeiro, depois os guias que as mencionam no resumo, e depois o resto.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Maiúsculas e acentos não importam, então *cafe* encontra *Café*. Cada palavra que você digita precisa aparecer em algum lugar do guia para que ele seja listado.',
				},
			],
		},
		{
			heading: 'Ajuda a partir da tela em que você está',
			blocks: [
				{
					type: 'p',
					text: 'Uma tela que tem um guia mostra um link **Como funciona** perto do título. Ele abre o guia dessa tela; quando vários guias tratam dela, abre uma lista curta para você escolher.',
				},
				{
					type: 'p',
					text: 'Alguns cartões e configurações têm um pequeno botão redondo *i*. Ele explica o recurso em uma ou duas frases e, quando um guia vai além, termina com **Ler o guia**.',
				},
			],
		},
		{
			heading: 'Como ler um guia',
			blocks: [
				{
					type: 'list',
					items: [
						'Os selos abaixo do título dizem a quais apps o guia se aplica e se você precisa de algo antes, como o Pro ou a função de administrador de clube.',
						'**Nesta página** lista as seções de um guia mais longo e vai direto para a que você escolher.',
						'**Guias relacionados**, no final, indica o que você provavelmente vai precisar em seguida.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Os guias aparecem no idioma configurado no app. Um guia que ainda não foi traduzido para esse idioma aparece em inglês, com um aviso no topo informando isso.',
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
