import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'refund-policies',
	title: 'Políticas de reembolso e cancelamento da sua inscrição',
	summary: 'Como funcionam as três políticas de reembolso, como um participante cancela uma inscrição paga e o que ele vê ao fazer isso.',
	sections: [
		{
			heading: 'Antes de começar',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'A inscrição paga ainda não está no ar. Ela exige a conta Stripe do organizador conectada e o sistema de pagamentos da plataforma ativado. Até lá, nenhum evento pode ser cobrado, então não há nada a reembolsar.',
				},
			],
		},
		{
			heading: 'As três políticas',
			blocks: [
				{
					type: 'p',
					text: 'O organizador escolhe uma **Política de reembolso** ao criar um evento pago. Ela define o que a pessoa recebe de volta se *ela* cancelar, e aparece na página do evento antes de alguém pagar.',
				},
				{
					type: 'list',
					items: [
						'**Reembolso total até o horário de início**: aparece para os participantes como **Cancelamento gratuito até o início do evento**.',
						'**Reembolso total até 24h antes**: aparece como **Cancelamento gratuito até 24 horas antes do início**. Esta é a opção padrão.',
						'**Sem reembolsos**: aparece como **Sem reembolso em caso de cancelamento**.',
					],
				},
				{
					type: 'p',
					text: 'O reembolso é tudo ou nada: dentro do prazo você recebe o valor integral de volta; fora dele, não recebe nada. O prazo é contado a partir do início da ocorrência em que você se inscreveu.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'A política só cobre o cancelamento feito pelo participante. Se o organizador cancelar uma aula, todos que pagaram são reembolsados integralmente, seja qual for a política: veja [[guide:cancel-a-class|Cancelar uma aula]].',
				},
			],
		},
		{
			heading: 'Cancelar sua própria inscrição',
			blocks: [
				{
					type: 'steps',
					items: [
						'Abra o evento na web. Onde aparece **Você está inscrito**, clique em **Cancelar inscrição**.',
						'Leia a caixa de diálogo. Dentro do prazo de reembolso, ela diz que você será reembolsado na forma de pagamento original e que sua vaga fica disponível para alguém da lista de espera.',
						'Clique em **Cancelar inscrição** para continuar, ou em **Manter minha vaga** para desistir.',
					],
				},
				{
					type: 'p',
					text: 'Quando o cancelamento é concluído, você vê **Reembolso iniciado — pode levar alguns dias para aparecer. Sua vaga foi liberada.** Até o seu banco confirmar, a página mostra **Reembolso em andamento**.',
				},
				{
					type: 'p',
					text: 'Se você saiu do pagamento antes de pagar, o mesmo botão cancela a inscrição pendente: a vaga reservada para você é liberada e nenhum pagamento é cobrado.',
				},
			],
		},
		{
			heading: 'Fora do prazo de reembolso',
			blocks: [
				{
					type: 'p',
					text: 'Depois do prazo, ou em um evento **Sem reembolsos**, o app não consegue cancelar sua inscrição por você. A caixa de diálogo avisa antes de você tentar, você mantém sua vaga e, se continuar mesmo assim, verá **Esta inscrição está fora do prazo de reembolso. Fale com o organizador para cancelar.**',
				},
			],
		},
		{
			heading: 'Se um reembolso não chegar',
			blocks: [
				{
					type: 'p',
					text: 'De vez em quando, um banco devolve um reembolso. A página do evento então mostra **Seu reembolso não chegou até você** e uma notificação diz **Um reembolso não foi concluído — vamos entrar em contato**. Você não precisa pagar de novo; use **Falar com o financeiro** e o valor será devolvido de outra forma.',
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
