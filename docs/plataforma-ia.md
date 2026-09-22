# Plataforma IA propia — plan para empezar

> ⏳ **Plan, no implementado.** Nombre provisional: **Núcleo IA**.

Una sola API de IA, nuestra, que usan todos los proyectos (Zuma primero). Los proyectos
nunca le hablan directo a DeepSeek, OpenRouter u OpenAI: le hablan a Núcleo IA, y Núcleo IA
decide qué modelo responde. Si un proveedor sube precios o se cae, se cambia en un solo lugar.

```
Zuma (agentes) ─┐
Proyecto 2 ─────┼──► Núcleo IA (http://nucleo-ia:4000) ──► DeepSeek / Qwen / Llama / Gemini
Clientes (API) ─┘     claves · enrutador · respaldo · costos      (por API; luego GPU propia)
```

## Decisiones

| Tema | Decisión | Por qué |
|---|---|---|
| Motor | **LiteLLM Proxy** (open source) | API compatible con OpenAI, claves virtuales, presupuestos, fallback y logs de costo ya hechos |
| Dónde vive | Repo aparte + stack Docker propio en el mismo servidor | No mezclarlo con Zuma; se reutiliza en otros proyectos |
| Red | Red Docker interna compartida; **no se expone a internet** al inicio | Solo los proyectos del servidor lo pueden llamar |
| Base de datos | Postgres (una base `nucleo_ia` nueva) | LiteLLM guarda ahí claves y gastos |
| Modelos | Alquilados por API al inicio | Sin comprar GPU hasta tener volumen |
| Formato | OpenAI (`/v1/chat/completions`) | Es lo que Zuma ya envía; migrar es casi solo configuración |

## Fase 0 — Probar en local (1 día)

Objetivo: levantar LiteLLM en la PC y hacerle peticiones.

`config.yaml`:

```yaml
model_list:
  # Nombres NUESTROS; los proyectos solo conocen estos.
  - model_name: zuma-rapido
    litellm_params:
      model: deepseek/deepseek-v4-flash
      api_key: os.environ/DEEPSEEK_API_KEY
  - model_name: zuma-vision
    litellm_params:
      model: openrouter/google/gemini-2.5-flash
      api_key: os.environ/OPENROUTER_API_KEY
  - model_name: zuma-vision-abierto
    litellm_params:
      model: openrouter/qwen/qwen2.5-vl-72b-instruct
      api_key: os.environ/OPENROUTER_API_KEY

router_settings:
  fallbacks:
    - zuma-vision: [zuma-vision-abierto]

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
```

Levantar:

```bash
docker run --rm -p 4000:4000 \
  -v $(pwd)/config.yaml:/app/config.yaml \
  -e DEEPSEEK_API_KEY=... -e OPENROUTER_API_KEY=... -e LITELLM_MASTER_KEY=sk-maestra \
  ghcr.io/berriai/litellm:main-stable --config /app/config.yaml
```

Primera petición:

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-maestra" -H "Content-Type: application/json" \
  -d '{"model":"zuma-rapido","messages":[{"role":"user","content":"Hola, ¿qué modelo eres?"}]}'
```

Checklist:

- [ ] Responde `zuma-rapido` (texto).
- [ ] Responde `zuma-vision` con una foto de la bodega (imagen en base64).
- [ ] Probar herramientas (`tools`) con una de Zuma, p. ej. `inventario_critico`.
- [ ] Apagar a propósito la clave de OpenRouter y ver que el fallback responde.

## Fase 1 — Montarlo en el servidor (staging)

- [ ] Repo `nucleo-ia` con `config.yaml`, `docker-compose.yml` y `.env.example`.
- [ ] Contenedores: `nucleo-ia` (LiteLLM) + base `nucleo_ia` en Postgres.
- [ ] Red Docker `ia-interna` compartida con los contenedores de staging de Zuma.
- [ ] Sin puerto público (o solo `127.0.0.1:4000` para pruebas con curl en el servidor).
- [ ] Crear una clave virtual por proyecto y ambiente, con presupuesto mensual:

```bash
curl http://127.0.0.1:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"key_alias":"zuma-staging","models":["zuma-rapido","zuma-vision","zuma-vision-abierto"],"max_budget":20}'
```

## Fase 2 — Conectar Zuma staging

El chat de texto ya lee la URL desde `.env`. Solo hay que apuntarlo:

```
DEEPSEEK_BASE_URL=http://nucleo-ia:4000/v1
DEEPSEEK_API_KEY=<clave virtual zuma-staging>
DEEPSEEK_MODEL=zuma-rapido
```

La visión **no** se puede apuntar todavía: `OpenRouterService::OPENROUTER_ENDPOINT` está fijo
en el código. Cambio pequeño necesario:

- [ ] Pasar el endpoint de visión a `config('services.openrouter.base_url')` con
      `OPENROUTER_BASE_URL` (default `https://openrouter.ai/api/v1`), con su test.
- [ ] `OPENROUTER_BASE_URL=http://nucleo-ia:4000/v1`, `OPENROUTER_MODEL_VISION=zuma-vision`.
- [ ] Reiniciar `app` y `worker` de staging (OPcache, ver `DESARROLLO-EN-SERVIDOR.md`).
- [ ] Probar en staging: chat IA del dueño, OCR de factura, agente WhatsApp.
- [ ] Revisar en LiteLLM el gasto por clave y la latencia.

## Fase 3 — Producción

- [ ] Clave `zuma-produccion` con su presupuesto.
- [ ] Mismo cambio de `.env` en producción + reinicio.
- [ ] Una semana en paralelo mirando errores y costos antes de quitar las claves directas.
- [ ] Alerta si Núcleo IA se cae (Zuma debe mostrar el mensaje de "IA no disponible" que ya tiene).

## Fase 4 — Los agentes de Zuma sobre Núcleo IA

Con Zuma ya pasando por Núcleo IA, los agentes de esta carpeta usan esos nombres de modelo:

| Agente | Modelo sugerido |
|---|---|
| Gerente (chat) | `zuma-rapido`; uno más potente para preguntas difíciles |
| Foto → inventario | `zuma-vision` con fallback abierto |
| Vigilante, Proveedores, Costeo | `zuma-rapido` (corren en jobs, importa el costo) |

## Fase 5 — Hacerlo producto (después)

- Capa propia en Laravel: proyectos, clientes, planes, cobro en pesos, panel de uso.
- Enrutador por dificultad (barato primero, potente si hace falta).
- Chat web con marca propia (Open WebUI o LibreChat).
- Exponer la API y el MCP de Zuma a terceros.
- Cuando el gasto por API lo justifique: GPU alquilada con vLLM y modelos abiertos propios.

## Riesgos

- **Punto único de falla:** si Núcleo IA cae, cae la IA de todos los proyectos. Mitigar con
  reinicio automático, health check y alerta.
- **Herramientas con modelos pequeños:** fallan más al elegir herramientas. Probar cada
  modelo con preguntas reales antes de ponerlo en producción.
- **Licencias:** revisar la de cada modelo antes de venderlo (Llama exige "Built with Llama").
- **Datos:** los prompts llevan datos de restaurantes; logs con retención corta y Ley 1581.
