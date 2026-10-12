/// Truncating untrusted text before it is written through PostgREST.
///
/// `slice` counts UTF-16 units, so a cap landing inside a surrogate pair leaves
/// half a character behind: `JSON.stringify` emits it as a bare `\ud83d`
/// escape, and Postgres refuses that JSON outright ("Unicode low surrogate must
/// follow a high surrogate"). For a batch insert that is the WHOLE batch — one
/// race name ending in a split emoji drops every result beside it. A value that
/// arrived ill-formed (a provider's JSON can carry a lone `\ud83d` escape just
/// as well) is repaired on the same pass; half a character is not one.

/// Drop every unpaired surrogate.
export function dropLoneSurrogates(value: string): string {
  let out = '';
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff) {
      const low = value.charCodeAt(i + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        out += value[i] + value[i + 1];
        i++;
      }
      continue;
    }
    if (code >= 0xdc00 && code <= 0xdfff) continue;
    out += value[i];
  }
  return out;
}

/// `value` trimmed and capped at `max` UTF-16 units, never leaving half a
/// character at the cut or anywhere else.
export function clipText(value: string, max: number): string {
  const trimmed = value.trim();
  const clipped = trimmed.length <= max ? trimmed : trimmed.slice(0, max);
  return dropLoneSurrogates(clipped).trim();
}
