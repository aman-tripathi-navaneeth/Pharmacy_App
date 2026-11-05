import { Body, Controller, Get, Headers, Param, Patch, Res } from '@nestjs/common';
import { IsString, Matches } from 'class-validator';
import type { Response } from 'express';
import { Public, type AuthUser } from '../common/auth/auth.guard.js';
import { CurrentUser } from '../common/auth/current-user.decorator.js';
import { TranslationsService } from './translations.service.js';

const LANG = /^[a-z]{2,3}(-[A-Z]{2})?$/;

class SetLanguageDto {
  @IsString() @Matches(LANG, { message: 'Invalid language code.' }) languageCode: string;
}

@Controller()
export class TranslationsController {
  constructor(private readonly translations: TranslationsService) {}

  /** Public: the language picker is also needed before sign-in. */
  @Public()
  @Get('languages')
  languages() {
    return this.translations.listLanguages();
  }

  /** Public, cacheable by catalog version (ETag → 304 when unchanged). */
  @Public()
  @Get('translations/:language')
  async catalog(
    @Param('language') language: string,
    @Headers('if-none-match') ifNoneMatch: string | undefined,
    @Res({ passthrough: true }) res: Response,
  ) {
    if (!LANG.test(language)) {
      res.status(404);
      return { error: { code: 'LANGUAGE_NOT_AVAILABLE', message: 'This language is not available.' } };
    }
    const body = await this.translations.catalog(language);
    const etag = `"${language}@${body.catalogVersion}"`;
    res.setHeader('ETag', etag);
    res.setHeader('Cache-Control', 'public, max-age=300');
    if (ifNoneMatch === etag) {
      res.status(304);
      return undefined;
    }
    return body;
  }

  @Get('users/me/language')
  myLanguage(@CurrentUser() user: AuthUser) {
    return this.translations.userLanguage(user.userId);
  }

  @Patch('users/me/language')
  setMyLanguage(@CurrentUser() user: AuthUser, @Body() dto: SetLanguageDto) {
    return this.translations.setUserLanguage(user.userId, dto.languageCode);
  }
}
