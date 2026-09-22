# Núcleo IA

Plataforma de IA propia. Lee `CONTEXTO.md` antes de trabajar: ahí están el porqué, las
decisiones tomadas, el estado actual y lo que sigue.

## Estructura

| Archivo | Qué es |
|---|---|
| `docker-compose.yml` | Contenedores: gateway LiteLLM (red del host) |
| `config.yaml` | Modelos para la PC de 48 GB |
| `config-laptop.yaml` | Modelos mínimos para el portátil sin GPU |
| `chat/index.html` | Chat de pruebas, un solo archivo, sin dependencias |
| `docs/` | Documentos de diseño traídos del repo de Zuma |

## Reglas

- Los proyectos solo conocen los nombres `zuma-rapido`, `zuma-chat` y `zuma-vision`. Cambiar el
  modelo real detrás no debe obligar a tocar ningún proyecto.
- Ollama corre en el host, no en Docker.
- El `.env` nunca se sube: lleva la clave maestra.
- Respuestas y documentos en español.
