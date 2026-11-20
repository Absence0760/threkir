// The brand marks the app renders, as Vite-hashed URLs, in one object so the
// client build carries them in one tiny shared chunk rather than one chunk per
// file: the code budget counts every file (decisions § 2603). `?no-inline`
// keeps each a same-origin URL rather than a `data:` URI, which the canvas
// video exports draw from.
import logoMark from './brand/logo-mark.svg?no-inline';
import wordmarkLight from './brand/wordmark-light.svg?no-inline';

export const BRAND_URLS = { logoMark, wordmarkLight };
