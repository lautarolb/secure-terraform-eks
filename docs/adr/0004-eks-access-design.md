# ADR 0004: Acceso al cluster EKS — endpoint privado, bastion vía SSM, IRSA para el CNI

## Estado

Implementado (M3), código validado, no aplicado a AWS. El bastion todavía no tiene RBAC
real dentro de Kubernetes (EKS Access Entries) — depende de que el cluster exista.

## Contexto

Por default, EKS expone el endpoint del API del control plane a todo internet (alcanzable
por cualquiera en la red, aunque protegido por auth IAM + RBAC) y le da al rol de los
nodos permisos amplios de red (ENIs/IPs) que terminan heredando todos los pods de ese nodo
— la guía oficial de AWS (*EKS Best Practices Guide*) señala este último punto
explícitamente: "\[la policy del CNI en el rol del nodo\] effectively allow all pods
running on a node to attach/detach ENIs... it is recommended that you update the aws-node
daemonset to use IRSA".

## Decisión

**1. Endpoint del API privado únicamente:** `endpoint_public_access = false`,
`endpoint_private_access = true`. El cluster no es alcanzable desde internet en absoluto,
ni para intentar autenticarse.

**2. Bastion host de acceso, sin SSH:** EC2 en subnet **privada** (sin IP pública), con un
Security Group **sin ninguna regla de entrada**. El acceso es exclusivamente vía **SSM
Session Manager**: ni el operador ni el bastion se llaman directamente entre sí — ambos
inician conexiones salientes hacia el servicio SSM de AWS, que arma la sesión interactiva
en el medio. Por eso no hace falta ningún puerto abierto ni IP pública. Sin llaves SSH que
gestionar (la llave privada nunca se sube a ningún servidor, eso sería un anti-patrón
independientemente del mecanismo elegido). Sesiones auditadas en CloudTrail.

El rol IAM del bastion tiene `AmazonSSMManagedInstanceCore` (permiso gestionado estándar
para que el agente SSM funcione) más un permiso mínimo extra e inline,
`eks:DescribeCluster` acotado a este cluster puntual, para poder armar el kubeconfig
localmente. El acceso real a los objetos de Kubernetes (RBAC) es un paso aparte, todavía
pendiente (EKS Access Entries, que necesitan que el cluster ya exista — mismo tipo de
dependencia que el OIDC issuer de IRSA).

Como el Security Group que EKS crea automáticamente para el control plane solo deja pasar
tráfico de los nodos por default, se agregó una `aws_security_group_rule` explícita
permitiendo al Security Group del bastion llegar por 443 a ese SG del cluster — sin esto,
el bastion no llegaría al endpoint privado aunque esté en la misma VPC.

**3. IRSA para el plugin CNI:** en vez de dejar `AmazonEKS_CNI_Policy` en el rol
compartido de los nodos (el default, y lo que señala la guía de AWS como riesgo), se creó
un role de IRSA dedicado. Su trust policy usa un `Federated` principal (el OIDC provider
del cluster) más una `Condition` que solo lo deja asumir a quien traiga un token OIDC cuyo
`sub` sea exactamente `system:serviceaccount:kube-system:aws-node` (el Service Account del
plugin CNI) y cuyo `aud` sea `sts.amazonaws.com`. Ningún otro pod del cluster, aunque
tenga un token válido del mismo cluster, cumple esa condición.

## Consecuencias

- Superficie de ataque mínima: cero puertos de entrada en todo el proyecto expuestos a
  internet, ni en el cluster ni en el bastion.
- Costo operativo extra: hace falta el bastion (una EC2 corriendo) para poder administrar
  el cluster en absoluto — no hay atajo sin él, a diferencia de dejar el endpoint público.
- El OIDC provider agrega una dependencia de provider nueva (`hashicorp/tls`, usado solo
  para leer el certificado del issuer y sacar su huella SHA1) — complejidad menor aceptada
  a cambio del beneficio de seguridad, validada contra la recomendación explícita de AWS
  para este escenario puntual.
- Falta un paso antes de que el bastion sea realmente útil: EKS Access Entries para darle
  RBAC dentro de Kubernetes, pendiente hasta que el cluster se aplique de verdad.

## Alternativa considerada y descartada

Endpoint público restringido a una IP fija (`public_access_cidrs`) — más simple (no
necesita bastion), pero sigue siendo alcanzable en principio desde internet, solo filtrado
por IP en la capa de API de AWS, no una superficie de ataque completamente cerrada como el
endpoint privado.
