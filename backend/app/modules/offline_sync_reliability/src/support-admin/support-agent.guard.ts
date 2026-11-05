import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import type { AuthedRequest } from '../common/auth/auth.guard.js';
import { StoreAccessService } from '../common/store-access/store-access.service.js';

/**
 * Platform support console: only active users with the SUPPORT_AGENT role.
 * Runs after the global JWT guard, so `req.user` is already verified.
 */
@Injectable()
export class SupportAgentGuard implements CanActivate {
  constructor(private readonly access: StoreAccessService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<AuthedRequest>();
    if (req.user && (await this.access.isSupportAgent(req.user.userId))) return true;
    throw new ForbiddenException({ code: 'SUPPORT_ONLY', message: 'Only platform support staff can use the support console.' });
  }
}
