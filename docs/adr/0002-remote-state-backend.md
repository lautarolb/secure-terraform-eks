# ADR 0002: Backend de state remoto — S3 con locking nativo, sin DynamoDB

## Estado

Implementado (M0).

## Contexto

El state de Terraform necesita vivir en un lugar compartido y durable (no en disco local),
y necesita locking para que dos `apply` concurrentes no corrompan el archivo. El patrón
clásico de la comunidad Terraform es S3 (storage) + DynamoDB (tabla de lock).

## Decisión

Bucket S3 para el state, con **locking nativo de S3** (`use_lockfile = true`) en vez de
DynamoDB. S3 soporta *conditional writes* desde 2024, así que el lock se resuelve con un
objeto `.tflock` en el mismo bucket — no hace falta una tabla aparte.

El backend usa **partial configuration** (Opción B): el código (`backend "s3" { key = ...
}`) es genérico y se versiona; los datos específicos de la cuenta (`bucket`, `region`,
`profile`) viven en `backend.hcl`, que está gitignored y se pasa con
`terraform init -backend-config=backend.hcl`.

## Consecuencias

- Un recurso menos para crear/mantener/pagar (aunque una tabla DynamoDB on-demand para
  locks es casi gratis igual, así que el ahorro real es más simplicidad que costo).
- Depende de una feature relativamente nueva de S3 — si algún día hay que usar una región o
  cuenta con una versión de proveedor/S3 que no la soporte, hay que volver al patrón
  DynamoDB clásico.
- El código del backend es genérico y público; ningún dato de cuenta específico queda en
  el repo.
