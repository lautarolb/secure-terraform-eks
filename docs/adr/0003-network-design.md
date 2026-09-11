# ADR 0003: Diseño de red — tamaño de subnets y NAT único

## Estado

Implementado (M1), código validado, no aplicado a AWS.

## Contexto

EKS necesita subnets privadas (para los nodos/pods) y públicas (para el NAT y, más
adelante, load balancers) en al menos 2 AZs. Hay que decidir el tamaño de cada subnet y
cuántos NAT Gateways usar.

## Decisión

VPC `10.0.0.0/16` en `us-east-1`, dos AZs (`us-east-1a`/`1b`):

- Privadas **`/20`** (`private_a` `10.0.0.0/20`, `private_b` `10.0.16.0/20`) — mucho más
  grandes de lo que un tamaño "típico" sugeriría. Razón: el **VPC CNI de EKS le asigna una
  IP de la VPC a cada POD**, no solo a cada nodo — un nodo puede correr decenas de pods,
  cada uno consumiendo una IP real de la subnet.
- Públicas **`/24`** (`public_a` `10.0.32.0/24`, `public_b` `10.0.33.0/24`) — mucho más
  chicas, porque ahí solo vive el NAT Gateway (y eventualmente load balancers), no pods.
- **Un solo NAT Gateway** (en `public_a`), compartido por las dos AZs, en vez de uno por AZ.

## Consecuencias

- El NAT único ahorra ~$32/mes frente a tener uno por AZ.
- A cambio, se pierde alta disponibilidad cross-AZ: si `us-east-1a` tiene un problema,
  `private_b` también se queda sin salida a internet, aunque su propia AZ esté sana —
  porque ambas subnets privadas dependen del mismo NAT. Trade-off aceptado a propósito
  para un proyecto de portfolio sin requisito real de HA productiva.
- El `vpc_config.subnet_ids` del cluster EKS incluye las 4 subnets (públicas y privadas),
  no solo las privadas — así el cluster ya conoce las públicas por si el día de mañana
  hace falta un load balancer internet-facing, sin tener que hacer un update del cluster
  para agregarlas.
