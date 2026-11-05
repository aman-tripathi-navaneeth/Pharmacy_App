import { BadRequestException, Injectable, PipeTransform } from '@nestjs/common';

@Injectable()
export class ModuleKeyPipe implements PipeTransform<string, string> {
  transform(value: string): string {
    if (!/^[a-z][a-z0-9_]{1,39}$/.test(value)) {
      throw new BadRequestException({ code: 'VALIDATION_FAILED', message: 'Invalid module key.' });
    }
    return value;
  }
}
