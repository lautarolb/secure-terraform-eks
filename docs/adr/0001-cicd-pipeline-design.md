# ADR 0001: Diseño de pipeline CI/CD (GitHub Actions)

## Estado

Propuesto — diseño acordado, `.yml` todavía no escrito (queda para cuando se implemente M6/M7).

## Contexto

El roadmap tiene dos milestones relacionados:

- **M6** — tfsec/checkov en el pipeline, falla el build con hallazgos de severidad alta.
- **M7** — `terraform plan` comentado en cada PR, `terraform apply` en merge a `main` con aprobación manual.

Restricciones que el diseño tiene que respetar (ya establecidas en el resto del proyecto):

- Nada de credenciales de larga vida guardadas como secrets si hay una alternativa — coherente con el enfoque de mínimo privilegio de M2/M3 (IAM roles, IRSA).
- El backend S3 ya tiene locking nativo (`use_lockfile`, M0) — corridas concurrentes del pipeline no deberían pisarse el state.

## Decisión

Dos workflows separados de GitHub Actions:

### 1. CI — dispara en cada Pull Request contra `master`

Jobs, todos "required status checks" en la protección de rama:

1. `fmt -check` + `terraform validate` + `tflint --recursive` (ya corren local vía `hooks/pre-commit`, M5 — acá se repiten en CI para no depender de que cada dev tenga el hook instalado).
2. `tfsec` / `checkov` — falla el job si hay hallazgos de severidad alta (M6).
3. `terraform plan -out=tfplan` — el plan se **sube como artifact** del workflow (no se descarta al terminar el job) y se **comenta en la PR** (vía `gh pr comment` o `actions/github-script`), para que el reviewer vea el diff sin correrlo local.

Si el job 2 falla, el botón de merge de la PR queda bloqueado.

### 2. CD — dispara en cada push a `master` (es decir, en cada merge)

Un solo job, `apply`, apuntando a un **GitHub Environment protegido** (Settings → Environments, con "required reviewers" configurado):

1. El job se pausa apenas arranca — no ejecuta nada hasta que un reviewer designado lo aprueba a mano desde la pestaña Actions ("Review deployments" → "Approve"). **Este click es el equivalente automatizado de la confirmación manual que se venía pidiendo en el chat** — el pipeline no elimina el control humano antes de tocar AWS, solo lo reubica.
2. Una vez aprobado, el job **descarga el mismo `tfplan` artifact** generado en el job 3 del CI (identificado por el SHA del commit mergeado) y corre `terraform apply tfplan` — **nunca vuelve a plantear de cero**, para garantizar que lo que se aplica es exactamente lo que el reviewer vio y aprobó en la PR, no un plan nuevo que pudo haber cambiado si algo se tocó en la cuenta mientras tanto.

### Autenticación AWS en CI

**OIDC**, no access keys guardadas como GitHub Secret. GitHub le presenta un token al configurar el `id-token: write` permission; un IAM role en la cuenta (trust policy condicionada al repo/branch específico) se lo cambia por credenciales temporales vía `sts:AssumeRoleWithWebIdentity` — mismo patrón que IRSA (M3), aplicado a GitHub Actions en vez de a un pod de Kubernetes.

## Mapeo con AWS CodePipeline/CodeBuild (referencia, para quien viene de ese mundo)

| CodePipeline/CodeBuild                                   | GitHub Actions                       |
| -------------------------------------------------------- | ------------------------------------ |
| CodePipeline (orquesta stages)                           | El workflow (`.yml`) entero          |
| Source stage (trigger)                                   | `on: pull_request` / `on: push`      |
| CodeBuild (contenedor efímero que corre `buildspec.yml`) | Un runner ejecutando un `job:`       |
| Phases del `buildspec.yml`                               | Los `steps:` dentro de un job        |
| Manual Approval action                                   | Environment con "required reviewers" |
| IAM role del proyecto CodeBuild                          | IAM role vía OIDC que asume el job   |

Diferencia real: en CodeBuild se elige la imagen del contenedor explícitamente; en GitHub Actions el runner (`ubuntu-latest`, típicamente) ya trae herramientas básicas — lo que falte (Terraform, tflint) se instala como paso del job.

## Alternativas consideradas

- **AWS CodePipeline/CodeBuild en vez de GitHub Actions**: descartado para este proyecto — el repo vive en GitHub, y usar Actions evita depender de una segunda cuenta/servicio de AWS solo para CI, además de ser lo esperable para quien revise el repo en GitHub.
- **Access keys de larga vida como GitHub Secret**: descartado — contradice el enfoque de mínimo privilegio del resto del proyecto (M2 IAM base, M3 IRSA); OIDC da credenciales temporales sin secretos que rotar o filtrar.
- **Re-planear en el job de CD en vez de reusar el artifact del CI**: descartado — introduce la posibilidad de aplicar un diff distinto al que el reviewer aprobó.

## Consecuencias

- El apply real a AWS sigue necesitando un click humano explícito, incluso automatizado — no hay riesgo de que un merge dispare gasto sin que alguien lo confirme.
- Hace falta configurar un IAM role de OIDC para GitHub Actions en la cuenta AWS antes de que el workflow de CD pueda correr — trabajo pendiente al implementar M7.
- El diseño no cubre rollback automático: si un `apply` falla a mitad de camino, se corrige hacia adelante (nuevo commit, nueva PR), no hay "revertir" nativo de Terraform.
