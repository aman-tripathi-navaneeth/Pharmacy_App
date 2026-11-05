import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsDateString,
  IsInt,
    IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Matches,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';

export const MAX_BATCH_SIZE = 50;
export const MAX_PAYLOAD_BYTES = 256 * 1024;

const KEY = /^[A-Za-z0-9_.:-]+$/;
const NAME = /^[a-z][a-z0-9_]*$/;

export class DeviceScopeDto {
  @IsUUID() storeId: string;
  @IsString() @Length(1, 64) @Matches(KEY) deviceId: string;
}

export class PushOperationDto {
  @IsUUID() clientOperationId: string;
  @IsString() @Length(8, 128) @Matches(KEY) idempotencyKey: string;
  @IsString() @Length(2, 40) @Matches(NAME) module: string;
  @IsString() @Length(2, 60) @Matches(NAME) operationType: string;
  @IsObject() payload: Record<string, unknown>;
  @IsOptional() @IsString() @Length(1, 128) entityId?: string;
  @IsOptional() @IsInt() @Min(0) baseVersion?: number;
  @IsOptional() @IsArray() @ArrayMaxSize(20) @IsUUID('all', { each: true }) dependsOn?: string[];
  @IsOptional() @IsDateString() clientCreatedAt?: string;
}

export class PushDto extends DeviceScopeDto {
  @IsOptional() @IsString() @Length(1, 20) platform?: string;
  @IsOptional() @IsString() @Length(1, 40) appVersion?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_BATCH_SIZE)
  @ValidateNested({ each: true })
  @Type(() => PushOperationDto)
  operations: PushOperationDto[];
}

export class PullQueryDto extends DeviceScopeDto {
  /** Opaque cursor returned by the previous pull; omit for a first full pull. */
  @IsOptional() @IsString() @Matches(/^\d{1,15}$/) cursor?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(500) limit?: number;
}

export class StoreScopeDto {
  @IsUUID() storeId: string;
  @IsOptional() @IsString() @Length(1, 64) @Matches(KEY) deviceId?: string;
}

export class CancelOperationDto extends DeviceScopeDto {
  @IsString() @Length(8, 128) @Matches(KEY) idempotencyKey: string;
  @IsString() @Length(2, 40) @Matches(NAME) module: string;
  @IsString() @Length(2, 60) @Matches(NAME) operationType: string;
}
