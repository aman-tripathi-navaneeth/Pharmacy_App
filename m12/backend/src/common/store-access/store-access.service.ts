import { ForbiddenException, Injectable } from '@nestjs/common';
import { and, eq } from 'drizzle-orm';
import { type Db, InjectDb } from '../../db/db.module.js';
import { storeMembers, stores, users } from '../../db/schema.js';

export interface StoreMembership {
  userId: string;
  storeId: string;
  role: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isUuid = (v: string) => UUID.test(v);

/**
 * Integration seam with the Authentication / Store-setup module.
 *
 * Reads `users`, `stores` and `store_members` and re-checks access on every sync
 * request: permissions may change while a device is offline, so a revoked user,
 * suspended shop or removed membership must not sync (spec §13).
 */
@Injectable()
export class StoreAccessService {
  constructor(@InjectDb() private readonly db: Db) {}

  async assertAccess(userId: string, storeId: string): Promise<StoreMembership> {
    if (!isUuid(storeId) || !isUuid(userId)) {
      throw this.denied('STORE_ACCESS_DENIED', 'You do not have access to this shop.');
    }
    const [row] = await this.db
      .select({ userStatus: users.status, storeStatus: stores.status, memberStatus: storeMembers.status, role: storeMembers.role })
      .from(users)
      .leftJoin(stores, eq(stores.id, storeId))
      .leftJoin(storeMembers, and(eq(storeMembers.userId, users.id), eq(storeMembers.storeId, storeId)))
      .where(eq(users.id, userId))
      .limit(1);

    if (!row || row.userStatus !== 'ACTIVE') {
      throw this.denied('USER_DISABLED', 'Your account is disabled. Contact your shop owner.');
    }
    if (row.storeStatus !== 'ACTIVE') {
      throw this.denied('STORE_SUSPENDED', 'This shop is suspended, so changes cannot sync.');
    }
    if (row.memberStatus !== 'ACTIVE') {
      throw this.denied('STORE_ACCESS_DENIED', 'You do not have access to this shop.');
    }
    return { userId, storeId, role: row.role! };
  }

  /** Support staff (users.roles contains SUPPORT_AGENT); null when not staff. */
  async isSupportAgent(userId: string): Promise<boolean> {
    if (!isUuid(userId)) return false;
    const [u] = await this.db.select({ status: users.status, roles: users.roles }).from(users).where(eq(users.id, userId)).limit(1);
    return !!u && u.status === 'ACTIVE' && u.roles.includes('SUPPORT_AGENT');
  }

  private denied(code: string, message: string) {
    return new ForbiddenException({ code, message });
  }
}
