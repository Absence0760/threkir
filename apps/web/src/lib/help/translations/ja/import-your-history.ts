import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: 'import-your-history',
	title: 'ランニングの履歴をインポートする',
	summary: 'Strava、Garminのエクスポート、またはスマートフォンのヘルスケアアプリから過去のランを取り込む方法と、GPXファイルの扱いについて説明します。',
	sections: [
		{
			heading: 'Stravaを連携して最近のランと新しいランを取り込む',
			blocks: [
				{
					type: 'steps',
					items: [
						'Webでは設定の[[route:/settings/integrations|連携]]を開き、Stravaカードで**連携する**を選択します。スマートフォンアプリでは**あなた**タブの**連携**を開き、Stravaをタップします。',
						'Stravaにサインインし、アクセスを許可します。',
						'過去90日分のラン、ウォーク、ハイキングがコピーされ、以降の新しいStravaアクティビティも自動的に取り込まれます。',
					],
				},
				{
					type: 'p',
					text: 'もう一度取り込むには**今すぐ同期**を選択します。Webでは、**さかのぼる期間**で最大1年前までさかのぼれます。',
				},
			],
		},
		{
			heading: 'Stravaのアーカイブ全体を取り込む',
			blocks: [
				{
					type: 'p',
					text: 'Stravaの連携で取り込めるのは最近のアクティビティだけです。何年分もの履歴を取り込むには、Stravaのデータエクスポートを使います。',
				},
				{
					type: 'steps',
					items: [
						'Stravaで「設定」、「マイアカウント」の順に進み、アーカイブをリクエストします。Stravaからzipファイルへのリンクがメールで届きます。',
						'Webでは[[route:/settings/integrations|連携]]を開き、**Strava エクスポートからの一括インポート**を見つけて**Strava エクスポートの zip を選択**を選択します。スマートフォンアプリでは**あなた**タブの**アカウント**を開き、**別のアプリからインポート**に進んで**Strava ZIPをインポート**をタップします。',
						'インポートが完了するまで待ちます。Stravaの連携などですでに取り込まれているランはスキップされるので、何度実行しても問題ありません。',
					],
				},
			],
		},
		{
			heading: 'GarminとFITファイル',
			blocks: [
				{
					type: 'p',
					text: 'Garmin Connectとの自動連携は、Garminの承認が必要なため、まだ利用できません。それまではWebでGarminのファイルをインポートできます。',
				},
				{
					type: 'steps',
					items: [
						'Garmin Connectで、「オリジナルをエクスポート」で1件のアクティビティをエクスポートして.fitファイルを取得するか、Garminアカウント管理からすべてのデータのエクスポートをリクエストします。',
						'Webでは[[route:/settings/integrations|連携]]を開き、**Garmin エクスポートからの一括インポート**を見つけて**Garmin エクスポートを選択**を選択します。',
						'.fitファイルまたはzipを選びます。すでにインポート済みのアクティビティはスキップされます。',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Androidでは、Garmin、Samsung、FitbitのアプリがHealth Connectに書き込んだワークアウトも**別のアプリからインポート**から取り込めます。iPhoneでは、同じカードがApple Healthのデータを読み込みます。',
				},
			],
		},
		{
			heading: 'GPXなどの単一ファイル',
			blocks: [
				{
					type: 'p',
					text: '単一のGPX、KML、KMZ、GeoJSON、TCXファイルは、履歴のランではなく、たどれるルートとしてインポートされます。Webでは[[route:/routes|ルート]]、アプリではルート一覧を開き、そこでインポートしてください。',
				},
				{
					type: 'p',
					text: 'StravaやGarminのエクスポートzipに含まれるGPXやTCXファイルはランとして読み込まれます。GPXアクティビティの履歴を追加するには、上記の一括インポートを使ってください。',
				},
			],
		},
		{
			heading: 'インポートされないものがある場合',
			blocks: [
				{
					type: 'p',
					text: '一部のアクティビティが取り込まれなかった場合、インポート結果にそれぞれのアクティビティとその理由（接続の切断や、読み込めなかったファイルなど）が一覧表示されます。もう一度インポートを実行すると再試行できます。すでに取り込まれたものはスキップされるので、重複することはありません。',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'インポートしたランには、ランのデフォルトプライバシー設定が適用されます。何年分ものランが一度に公開されるのを避けたい場合は、大量にインポートする前に確認してください。[[guide:your-data-and-privacy|あなたのデータとプライバシー]]を参照してください。',
				},
			],
		},
	],
	sources: {
		title: '078b29389d32808d',
		summary: '440ddd94eca0b542',
		's0.heading': '69858eb69781e59e',
		's0.b0.i0': '92767a2a2bf7c191',
		's0.b0.i1': '8c05e0ad16ddb8c2',
		's0.b0.i2': '828e8880f5239f1c',
		's0.b1': '4302ec5e7767e8ab',
		's1.heading': '8abf228027d2a4fd',
		's1.b0': 'cf7faaa4679e66f2',
		's1.b1.i0': '9e771e203c299ace',
		's1.b1.i1': 'a6d02ee139faa051',
		's1.b1.i2': '0212bc406356fd62',
		's2.heading': 'f3f586814898940a',
		's2.b0': '25c859eb00073fae',
		's2.b1.i0': 'f82bc798e8ec1b4e',
		's2.b1.i1': '21d706b389df8c6a',
		's2.b1.i2': '69a212e6bb305cfc',
		's2.b2': '7d501c5e8de3d96e',
		's3.heading': '8b42dffcf7f0d635',
		's3.b0': '0dba61c98d441dad',
		's3.b1': '5dbef244bd55926e',
		's4.heading': '35509c7701b9dabc',
		's4.b0': '26a0daac64b29af6',
		's4.b1': '69e6cfdbe0110cea',
	},
};
