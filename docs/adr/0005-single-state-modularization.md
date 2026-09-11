# ADR 0005: Módulos de Terraform, pero un solo state

## Estado

Implementado (M4).

## Contexto

El roadmap original de M4 pedía "dividir en stacks pequeños y componibles" — la idea de
que cada pieza (red, IAM, EKS) tenga su propio ciclo de vida y radio de impacto aislado,
para que un `apply` de una parte no pueda romper otra por accidente.

Hay una distinción importante que no es obvia al leer "modularizar" literalmente: los
**módulos de Terraform** (`module "x" { source = "./modules/x" }`) son un mecanismo de
**organización de código** — variables/outputs limpios, reutilización — pero **no separan
el state por sí solos**. Si tres módulos se siguen llamando desde el mismo root, siguen
escribiendo al mismo `.tfstate`. Aislar de verdad el blast radius requiere **stacks
separados**: directorios raíz independientes, cada uno con su propio `backend.hcl`/state,
conectados entre sí leyendo outputs vía `terraform_remote_state` en vez de `module`.

## Decisión

Se modularizó el código (`infra/modules/{network,iam,eks}`, llamados desde
`infra/modules.tf`) **manteniendo un solo state compartido**, no stacks separados. Decisión
explícita del usuario, evaluando el trade-off consciente en vez de asumir que "modularizar"
implicaba automáticamente aislamiento de state.

Boundaries de los tres módulos:
- `network`: VPC, subnets, IGW, NAT, route tables.
- `iam`: cluster role + node role de EKS (sin dependencias de red).
- `eks`: cluster, node group, IRSA del CNI, y el **bastion completo** — agrupado acá porque
  todo depende del "ecosistema" del cluster (su Security Group, su ARN, su OIDC issuer), no
  de la red ni de IAM directamente.

## Consecuencias

- Se gana reutilización y prolijidad: variables/outputs explícitos por módulo, y cada uno
  ahora declara su propio `required_providers` (buena práctica para módulos reutilizables,
  detectada por tflint — ver M5).
- **No se gana aislamiento de blast radius**: un `apply` que toque `eks` puede, en
  principio, seguir afectando `network`/`iam` en la misma operación, porque comparten
  state y lock. Esto es exactamente el mismo problema de M2 (rol del nodo + rol del cluster
  en el mismo state que la red), sin resolver por la modularización.
- Menos overhead operativo a cambio: un solo `init`/`plan`/`apply` en vez de tres stacks
  separados wireados manualmente vía `terraform_remote_state`.
- **Revisitar esta decisión** si el proyecto necesita algún día pipelines de CI
  independientes por stack (por ejemplo, si `network` casi no cambia pero `eks` sí, y se
  quiere poder iterar sobre `eks` sin re-planear/aplicar la red en cada corrida).
