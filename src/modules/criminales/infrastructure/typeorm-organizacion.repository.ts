import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { PageResult } from '../../../shared/application/pagination/page-result';
import { Organizacion } from '../domain/organizacion.entity';
import type {
  FiltroOrganizaciones,
  OrganizacionRepositoryPort,
} from '../domain/organizacion.repository.port';

@Injectable()
export class TypeOrmOrganizacionRepository implements OrganizacionRepositoryPort {
  constructor(@InjectRepository(Organizacion) private readonly repo: Repository<Organizacion>) {}

  buscarPorId(id: string): Promise<Organizacion | null> {
    return this.repo.findOne({ where: { id } });
  }

  /** Sin distinguir mayusculas, igual que el indice unico sobre lower(nombre). */
  buscarPorNombre(nombre: string): Promise<Organizacion | null> {
    return this.repo
      .createQueryBuilder('org')
      .where('LOWER(org.nombre) = LOWER(:nombre)', { nombre })
      .getOne();
  }

  async listar(filtro: FiltroOrganizaciones): Promise<PageResult<Organizacion>> {
    const query = this.repo.createQueryBuilder('org');
    if (filtro.q) query.andWhere('org.nombre ILIKE :q', { q: `%${filtro.q}%` });
    if (filtro.categoria) query.andWhere('org.categoria = :cat', { cat: filtro.categoria });
    if (filtro.tipoAgrupacion) {
      query.andWhere('org.tipo_agrupacion = :tipo', { tipo: filtro.tipoAgrupacion });
    }
    if (filtro.zonaInfluenciaId) {
      query.andWhere('org.zona_influencia_id = :zona', { zona: filtro.zonaInfluenciaId });
    }
    if (filtro.activa !== undefined) {
      query.andWhere('org.activa = :activa', { activa: filtro.activa });
    }

    const [data, total] = await query
      .orderBy('org.nombre', 'ASC')
      .skip((filtro.page - 1) * filtro.limit)
      .take(filtro.limit)
      .getManyAndCount();
    return new PageResult(data, total, filtro.page, filtro.limit);
  }

  guardar(organizacion: Organizacion): Promise<Organizacion> {
    return this.repo.save(organizacion);
  }
}
