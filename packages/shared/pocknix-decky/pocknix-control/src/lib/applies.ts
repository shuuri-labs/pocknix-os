export const APPLIES_NOW = "Applies now";
export const APPLIES_NEXT_LAUNCH = "Applies on next launch";

/** Now and next launch only differ while a running game uses the settings being edited; at any
 *  other time everything takes effect when a game starts, which one note says instead. */
export const timed = (live: boolean, when: string, text?: string) => (live ? (text ? `${when}. ${text}` : when) : text);
