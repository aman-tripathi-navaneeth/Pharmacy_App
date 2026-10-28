import { Injectable } from '@nestjs/common';
import { IsIn, IsInt, IsOptional, IsString, Length, Max, Min, NotEquals } from 'class-validator';
import { and, eq, sql } from 'drizzle-orm';
import { stockBalances, stockMovements } from '../../../db/schema.js';
import { DomainRejectedError, HandlerResult, OperationContext, OperationHandler } from '../operation-handler.js';

export class StockMovementPayload {
  @IsString() @Length(1, 64) productId: string;
  @IsOptional() @IsString() @Length(1, 64) batchNo?: string;
  @IsInt() @NotEquals(0) @Min(-100_000) @Max(100_000) quantityDelta: number;
  @IsIn(['SALE', 'PURCHASE', 'ADJUSTMENT', 'RETURN', 'EXPIRY']) reason: string;
  @IsOptional() @IsString() @Length(1, 64) referenceId?: string;
  @IsOptional() @IsString() @Length(0, 200) note?: string;
}

/**
 * REFERENCE handler for the Inventory owner to adopt or replace (spec §6, §14):
 * stock is an append-only ledger keyed by the client operation id; the server owns the
 * balance and rejects movements that would make it negative. Clients never send a balance.
 */
@Injectable()
export class StockMovementHandler implements OperationHandler<StockMovementPayload> {
  readonly module = 'inventory';
  readonly operationType = 'stock_movement';
  readonly payloadType = StockMovementPayload;

  async handle(ctx: OperationContext, p: StockMovementPayload): Promise<HandlerResult> {
    const { tx, storeId } = ctx;
    const key = and(eq(stockBalances.storeId, storeId), eq(stockBalances.productId, p.productId));

    // Make sure the balance row exists, then lock it: concurrent movements for the same
    // product queue here, so the availability check below can't race.
    await tx.insert(stockBalances).values({ storeId, productId: p.productId }).onConflictDoNothing();
    const [balance] = await tx.select().from(stockBalances).where(key).for('update');

    if (balance.quantity + p.quantityDelta < 0) {
      throw new DomainRejectedError(
        'INSUFFICIENT_STOCK',
        `Stock quantity exceeds available balance (available ${balance.quantity}, requested ${-p.quantityDelta}).`,
      );
    }

    const [movement] = await tx
      .insert(stockMovements)
      .values({
        storeId,
        movementId: ctx.clientOperationId,
        productId: p.productId,
        batchNo: p.batchNo,
        quantityDelta: p.quantityDelta,
        reason: p.reason,
        referenceId: p.referenceId,
        note: p.note,
        createdBy: ctx.userId,
        deviceId: ctx.deviceId,
      })
      .returning({ id: stockMovements.id });

    const [updated] = await tx
      .update(stockBalances)
      .set({
        quantity: sql`${stockBalances.quantity} + ${p.quantityDelta}`,
        version: sql`${stockBalances.version} + 1`,
        updatedAt: new Date(),
      })
      .where(key)
      .returning({ quantity: stockBalances.quantity, version: stockBalances.version });

    await ctx.emitChange({
      entity: 'stock_balance',
      entityId: p.productId,
      version: updated.version,
      data: { productId: p.productId, quantity: updated.quantity },
    });
    return { resourceId: movement.id, version: updated.version };
  }
}
