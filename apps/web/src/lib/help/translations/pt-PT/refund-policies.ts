import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'refund-policies',
	title: 'Políticas de reembolso e cancelar a sua inscrição',
	summary: 'Como funcionam as três políticas de reembolso, como um participante cancela uma inscrição paga e o que vê quando o faz.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'A inscrição paga ainda não está disponível. Precisa da conta Stripe do organizador ligada e da inscrição paga ativada pela plataforma. Até lá, nenhum evento pode ser cobrado, por isso não há nada a reembolsar.',
				},
			],
		},
		{
			heading: 'As três políticas',
			blocks: [
				{
					type: 'p',
					text: 'O organizador escolhe uma **Política de reembolso** ao criar um evento pago. Ela determina o que alguém recebe de volta se for *essa pessoa* a cancelar, e é mostrada na página do evento antes de alguém pagar.',
				},
				{
					type: 'list',
					items: [
						'**Reembolso total até à hora de início**: mostrada aos participantes como **Cancelamento gratuito até o início do evento**.',
						'**Reembolso total até 24h antes**: mostrada como **Cancelamento gratuito até 24 horas antes do início**. É a predefinição.',
						'**Sem reembolsos**: mostrada como **Sem reembolso em caso de cancelamento**.',
					],
				},
				{
					type: 'p',
					text: 'Um reembolso é tudo ou nada: dentro do prazo recebe o preço total de volta, fora dele não recebe nada. O prazo é contado em relação ao início da ocorrência em que se inscreveu.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'A política só abrange o cancelamento por parte de um participante. Se o organizador cancelar uma aula, todos os que pagaram são reembolsados na totalidade, seja qual for a política: consulte [[guide:cancel-a-class|Cancelar uma aula]].',
				},
			],
		},
		{
			heading: 'Cancelar a sua própria inscrição',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o evento na web. Onde diz **Está inscrito**, prima **Cancelar inscrição**.',
						'Leia a caixa de diálogo. Dentro do prazo de reembolso, indica que será reembolsado no seu método de pagamento original e que o seu lugar fica disponível para alguém na lista de espera.',
						'Prima **Cancelar inscrição** para avançar, ou **Manter o meu lugar** para desistir.',
					],
				},
				{
					type: 'p',
					text: 'Depois de concluído, vê **Reembolso iniciado — pode levar alguns dias para aparecer. O seu lugar foi libertado.** Até o seu banco o confirmar, a página mostra **Reembolso a decorrer**.',
				},
				{
					type: 'p',
					text: 'Se saiu da página de pagamento antes de pagar, o mesmo botão cancela a inscrição pendente: o seu lugar reservado é libertado e não é cobrado qualquer pagamento.',
				},
			],
		},
		{
			heading: 'Fora do prazo de reembolso',
			blocks: [
				{
					type: 'p',
					text: 'Depois do prazo, ou num evento com **Sem reembolsos**, a app não pode cancelar a sua inscrição por si. A caixa de diálogo avisa-o antes de tentar, mantém o seu lugar e, se avançar, verá **Esta inscrição está fora do prazo de reembolso. Fale com o organizador para cancelar.**',
				},
			],
		},
		{
			heading: 'Se um reembolso não chegar',
			blocks: [
				{
					type: 'p',
					text: 'Ocasionalmente, um banco devolve um reembolso. A página do evento mostra então **O seu reembolso não chegou** e uma notificação diz **Um reembolso não foi concluído — entraremos em contacto**. Não precisa de pagar novamente; use **Contactar a faturação** e o valor ser-lhe-á devolvido por outra via.',
				},
			],
		},
	],
	sources: {
		title: 'c4fa256f459076d1',
		summary: '9baf65491beccb1b',
		's0.heading': '74e492d5d0df0bab',
		's0.b0': '30a11867ccf5b3d2',
		's1.heading': '9b547a04e62b40db',
		's1.b0': 'ac02c018440619c7',
		's1.b1.i0': '78212cc5dd0fc966',
		's1.b1.i1': '109e0ad8958dff1d',
		's1.b1.i2': 'c0df4938a31c7529',
		's1.b2': 'f6431402b8fb3d47',
		's1.b3': '2ba18e4b6ad11943',
		's2.heading': '75a59fd46f7b58e9',
		's2.b0.i0': '6acdfa50019e0f37',
		's2.b0.i1': '46cf562b1c2b6db6',
		's2.b0.i2': '769ffd95161fd1d5',
		's2.b1': '36a76c72aba97bcd',
		's2.b2': '3cd5377cc8a2bfcf',
		's3.heading': '41bf02bef2f3e906',
		's3.b0': '79864fedf6e2a3a4',
		's4.heading': '9bc91646456ca461',
		's4.b0': '99e677611ddc18a9',
	},
};
