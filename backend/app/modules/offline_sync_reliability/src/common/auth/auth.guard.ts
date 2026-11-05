import {
  CanActivate,
  ExecutionContext,
  Injectable,
  SetMetadata,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import type { Request } from 'express';

export const IS_PUBLIC = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC, true);

export interface AuthUser {
  userId: string;
}

export type AuthedRequest = Request & { user: AuthUser; requestId: string };

/**
 * Verifies the bearer token issued by the shared authentication module.
 * Member 12 does not issue tokens; it only consumes `sub` (the user id).
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const req = context.switchToHttp().getRequest<AuthedRequest>();
    const [scheme, token] = (req.headers.authorization ?? '').split(' ');
    if (scheme !== 'Bearer' || !token) {
      throw new UnauthorizedException({ code: 'AUTH_REQUIRED', message: 'Sign in again to continue syncing.' });
    }
    try {
      const payload = await this.jwt.verifyAsync<{ sub: string }>(token);
      req.user = { userId: payload.sub };
      return true;
    } catch {
      throw new UnauthorizedException({ code: 'AUTH_EXPIRED', message: 'Your session expired. Sign in again to continue syncing.' });
    }
  }
}
