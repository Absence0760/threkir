import type { MessageKey } from '../i18n/messages';
import type { DmRelation } from './dm_recipients';

/// The line under a person in a recipient picker saying how the two of you
/// are connected, which is also why a message to them is admitted.
export function dmRelationLabelKey(relation: DmRelation): MessageKey {
	if (relation === 'mutual') return 'routeDetail.sendDm.relationMutual';
	if (relation === 'follows_you') return 'routeDetail.sendDm.relationFollowsYou';
	return 'routeDetail.sendDm.relationYouFollow';
}
