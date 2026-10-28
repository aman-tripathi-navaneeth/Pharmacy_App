import { Module } from '@nestjs/common';
import { ProductTourController } from './product-tour.controller.js';
import { ProductTourService } from './product-tour.service.js';

@Module({
  controllers: [ProductTourController],
  providers: [ProductTourService],
})
export class ProductTourModule {}
