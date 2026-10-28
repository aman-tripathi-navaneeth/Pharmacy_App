import type { AuthorRole, TicketStatus } from '../db/schema.js';

/**
 * Suggested lifecycle (spec §8.2): OPEN → IN_PROGRESS → WAITING_FOR_USER (optional)
 * → RESOLVED → CLOSED. Support staff drive it; a shop user may only close (withdraw)
 * their own ticket. CLOSED is final — a new problem gets a new ticket.
 */
const SUPPORT_TRANSITIONS: Record<TicketStatus, TicketStatus[]> = {
  OPEN: ['IN_PROGRESS', 'WAITING_FOR_USER', 'RESOLVED', 'CLOSED'],
  IN_PROGRESS: ['WAITING_FOR_USER', 'RESOLVED', 'CLOSED'],
  WAITING_FOR_USER: ['IN_PROGRESS', 'RESOLVED', 'CLOSED'],
  RESOLVED: ['IN_PROGRESS', 'CLOSED'],
  CLOSED: [],
};

const USER_TRANSITIONS: Record<TicketStatus, TicketStatus[]> = {
  OPEN: ['CLOSED'],
  IN_PROGRESS: ['CLOSED'],
  WAITING_FOR_USER: ['CLOSED'],
  RESOLVED: ['CLOSED'],
  CLOSED: [],
};

export function canTransition(role: AuthorRole, from: TicketStatus, to: TicketStatus): boolean {
  return (role === 'SUPPORT' ? SUPPORT_TRANSITIONS : USER_TRANSITIONS)[from].includes(to);
}

/** Days after resolution during which a user reply reopens the ticket. */
export const REOPEN_WINDOW_DAYS = 14;

/**
 * Status after a reply:
 *  - user answers a WAITING_FOR_USER ticket → back to IN_PROGRESS;
 *  - user replies to a RESOLVED ticket within the window → reopened (OPEN);
 *  - support replies to an OPEN ticket → IN_PROGRESS.
 * Returns null when the status should not change.
 */
export function statusAfterReply(
  role: AuthorRole,
  current: TicketStatus,
  resolvedAt: Date | undefined,
  now = new Date(),
): TicketStatus | null {
  if (role === 'USER') {
    if (current === 'WAITING_FOR_USER') return 'IN_PROGRESS';
    if (current === 'RESOLVED' && resolvedAt && now.getTime() - resolvedAt.getTime() <= REOPEN_WINDOW_DAYS * 86_400_000) {
      return 'OPEN';
    }
    return null;
  }
  return current === 'OPEN' ? 'IN_PROGRESS' : null;
}

/** A user may reply unless the ticket is closed, or resolved past the reopen window. */
export function canUserReply(current: TicketStatus, resolvedAt: Date | undefined, now = new Date()): boolean {
  if (current === 'CLOSED') return false;
  if (current === 'RESOLVED') return statusAfterReply('USER', current, resolvedAt, now) !== null;
  return true;
}
