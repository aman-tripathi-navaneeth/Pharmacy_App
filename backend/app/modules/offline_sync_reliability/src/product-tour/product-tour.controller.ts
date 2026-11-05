import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { IsIn, IsString, Matches } from 'class-validator';
import { Public, type AuthUser } from '../common/auth/auth.guard.js';
import { CurrentUser } from '../common/auth/current-user.decorator.js';
import { ProductTourService } from './product-tour.service.js';
import { TOUR_STATUSES, type TourStatus } from '../db/schema.js';

const VERSION = /^(latest|\d+(\.\d+)+)$/;

class ProgressQueryDto {
  @IsString() @Matches(VERSION) version: string;
}

class SaveProgressDto {
  @IsString() @Matches(/^\d+(\.\d+)+$/) tourVersion: string;
  @IsString() @Matches(/^[a-zA-Z][a-zA-Z0-9]{0,39}$/) stepId: string;
  @IsIn(TOUR_STATUSES) status: TourStatus;
}

@Controller('product-tour')
export class ProductTourController {
  constructor(private readonly tours: ProductTourService) {}

  // Declared before ':version' so "progress" is not read as a version.
  @Get('progress')
  progress(@CurrentUser() user: AuthUser, @Query() q: ProgressQueryDto) {
    return this.tours.getProgress(user.userId, q.version);
  }

  /** POST /product-tour/progress — step viewed, skipped or completed. */
  @Post('progress')
  save(@CurrentUser() user: AuthUser, @Body() dto: SaveProgressDto) {
    return this.tours.saveProgress(user.userId, dto);
  }

  /** GET /product-tour/:version — content (translation keys); `latest` for the newest. */
  @Public()
  @Get(':version')
  tour(@Param('version') version: string) {
    return this.tours.tour(VERSION.test(version) ? version : '__invalid__');
  }
}
