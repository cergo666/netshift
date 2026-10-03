import { NetShift } from '../../types';

const GROUP_TYPES = ['urltest', 'selector'];

// The server list ordered by delay: the fastest first, servers without a
// measurement (0) last, equal delays keep their order. Group entries such as
// "Fastest" are not servers and stay where they are, in front of the list.
export function sortOutboundsByLatency(
  outbounds: NetShift.Outbound[],
): NetShift.Outbound[] {
  const isGroup = (item: NetShift.Outbound) =>
    GROUP_TYPES.includes(item.type.toLowerCase());
  const groups = outbounds.filter(isGroup);
  const servers = outbounds
    .filter((item) => !isGroup(item))
    .map((item, index) => ({ item, index }))
    .sort((a, b) => {
      const left = a.item.latency > 0 ? a.item.latency : Infinity;
      const right = b.item.latency > 0 ? b.item.latency : Infinity;

      if (left === right) {
        return a.index - b.index;
      }

      return left < right ? -1 : 1;
    })
    .map(({ item }) => item);

  return [...groups, ...servers];
}
