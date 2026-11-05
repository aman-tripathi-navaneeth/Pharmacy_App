import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import type { Response } from 'express';
import type { AuthedRequest } from '../auth/auth.guard.js';

/** Every error leaves the API as `{ error: { code, message, requestId, details? } }`. */
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('HttpError');

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const res = ctx.getResponse<Response>();
    const req = ctx.getRequest<AuthedRequest>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let code = 'INTERNAL_ERROR';
    let message = 'Something went wrong on the server. Your changes are still saved on this device.';
    let details: unknown;

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse();
      if (typeof body === 'object' && body !== null) {
        const b = body as Record<string, unknown>;
        code = typeof b.code === 'string' ? b.code : defaultCode(status);
        if (Array.isArray(b.message)) {
          message = 'Some fields are invalid.';
          details = b.message;
        } else if (typeof b.message === 'string') {
          message = b.message;
        }
      } else {
        code = defaultCode(status);
        message = String(body);
      }
    } else {
      this.logger.error(`[${req.requestId}] ${(exception as Error)?.stack ?? exception}`);
    }

    res.status(status).json({ error: { code, message, requestId: req.requestId, ...(details ? { details } : {}) } });
  }
}

function defaultCode(status: number): string {
  switch (status) {
    case 400: return 'VALIDATION_FAILED';
    case 401: return 'AUTH_REQUIRED';
    case 403: return 'FORBIDDEN';
    case 404: return 'NOT_FOUND';
    case 409: return 'CONFLICT';
    case 413: return 'PAYLOAD_TOO_LARGE';
    case 429: return 'RATE_LIMITED';
    default: return status >= 500 ? 'INTERNAL_ERROR' : 'REQUEST_FAILED';
  }
}
