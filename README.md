# LMS DevOps Platform

Infrastructure DevOps pour une plateforme LMS déployée sur **Google Cloud Platform**.

## Technologies utilisées

- Terraform (Infrastructure as Code)
- Google Cloud Platform
- GKE (Kubernetes)
- Compute Engine
- Docker
- Jenkins
- SonarQube

## Infrastructure

Terraform déploie automatiquement :

- un **VPC custom**
- les **subnets GKE, STAGING et PROD**
- un **cluster GKE** pour CI/CD et environnement DEV
- deux **VM Compute Engine** pour STAGING et PROD
- **Artifact Registry** pour les images Docker
- les **règles firewall et Cloud NAT**

## Scripts Terraform

Les scripts Terraform sont **modulables et paramétrables**.

Les valeurs spécifiques (project_id, region, zone, etc.) sont définies via des **variables**, ce qui permet de réutiliser facilement les scripts dans différents environnements.
