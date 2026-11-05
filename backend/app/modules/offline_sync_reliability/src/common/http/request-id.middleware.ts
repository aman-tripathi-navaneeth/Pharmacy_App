import { Injectable, NestMiddleware } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';

const SAFE_ID = /^[A-Za-z0-9._-]{1,64}$/;

@Injectable()
export class RequestIdMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const incoming = req.header('x-request-id');
    const id = incoming && SAFE_ID.test(incoming) ? incoming : randomUUID();
    (req as Request & { requestId: string }).requestId = id;
    res.setHeader('x-request-id', id);
    next();
  }
}
