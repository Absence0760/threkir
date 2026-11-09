import type { PageLoad } from './$types';

export const load: PageLoad = ({ params }) => {
	return { region: params.region, park: params.park, course: params.course };
};
