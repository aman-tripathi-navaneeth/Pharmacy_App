import { Injectable } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsEmail, IsOptional, IsString, Length, Matches, ValidateNested } from 'class-validator';
import { eq } from 'drizzle-orm';
import { shopProfiles } from '../../../db/schema.js';
import { DomainConflictError, DomainRejectedError, HandlerResult, OperationContext, OperationHandler } from '../operation-handler.js';

export class ShopProfileFields {
  @IsOptional() @IsString() @Length(2, 120) name?: string;
  @IsOptional() @IsString() @Matches(/^\+?[0-9 ]{7,20}$/, { message: 'phone must be a valid phone number' }) phone?: string;
  @IsOptional() @IsString() @Length(3, 300) address?: string;
  @IsOptional() @IsEmail() email?: string;
}

export class ShopProfilePayload {
  @ValidateNested() @Type(() => ShopProfileFields) fields: ShopProfileFields;
}

const EDITABLE = ['name', 'phone', 'address', 'email'] as const;
type Editable = (typeof EDITABLE)[number];

/**
 * REFERENCE handler: optimistic concurrency for shop/profile fields (spec §6).
 * The client sends the version it edited (`baseVersion`). If the server moved on, the change is
 * NOT applied; the client receives both values and the user decides (screen E1).
 */
@Injectable()
export class ShopProfileHandler implements OperationHandler<ShopProfilePayload> {
  readonly module = 'shop';
  readonly operationType = 'profile_update';
  readonly payloadType = ShopProfilePayload;

  async handle(ctx: OperationContext, p: ShopProfilePayload): Promise<HandlerResult> {
    const fields = Object.fromEntries(EDITABLE.filter((k) => p.fields[k] !== undefined).map((k) => [k, p.fields[k]])) as Partial<
      Record<Editable, string>
    >;
    if (!Object.keys(fields).length) throw new DomainRejectedError('NO_CHANGES', 'No profile fields were changed.');
    if (ctx.baseVersion === undefined) {
      throw new DomainRejectedError('BASE_VERSION_REQUIRED', 'Profile edits must include the version they were based on.');
    }

    const { tx, storeId } = ctx;
    await tx.insert(shopProfiles).values({ storeId }).onConflictDoNothing();
    const [current] = await tx.select().from(shopProfiles).where(eq(shopProfiles.storeId, storeId)).for('update');

    if (ctx.baseVersion !== current.version) {
      throw new DomainConflictError('VERSION_CONFLICT', 'Shop profile changed on another device.', {
        entity: 'shop_profile',
        entityId: storeId,
        serverVersion: current.version,
        serverUpdatedAt: current.version ? current.updatedAt.toISOString() : undefined,
        serverValues: Object.fromEntries(Object.keys(fields).map((k) => [k, current[k as Editable] ?? null])),
        clientValues: fields,
        clientBaseVersion: ctx.baseVersion,
      });
    }

    const [updated] = await tx
      .update(shopProfiles)
      .set({ ...fields, version: current.version + 1, updatedAt: new Date(), updatedBy: ctx.userId })
      .where(eq(shopProfiles.storeId, storeId))
      .returning();

    const data = Object.fromEntries(EDITABLE.map((k) => [k, updated[k] ?? null]));
    await ctx.emitChange({ entity: 'shop_profile', entityId: storeId, version: updated.version, data: { ...data, updatedAt: updated.updatedAt } });
    return { resourceId: storeId, version: updated.version };
  }
}
