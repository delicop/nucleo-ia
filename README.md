# Núcleo IA — laboratorio local

API de IA propia. Los proyectos (Zuma y los que vengan) le hablan **solo a esto**, nunca
directo a DeepSeek, OpenAI o Google. Por detrás puede haber modelos locales (Ollama, vLLM)
o modelos por API: cambiarlo no toca el código de los proyectos.

```
Chat web (Open WebUI :3000)  ──┐
Zuma / otros proyectos       ──┼──► Núcleo IA (LiteLLM :4000) ──► Ollama :11434
curl / scripts               ──┘         claves · fallback · costos    (modelos locales)
```

El chat guarda la conversación y la reenvía completa en cada pregunta: por eso se puede
**cambiar de modelo a mitad de la charla sin perder el contexto**.

## Modelos publicados

| Nombre (el que usan los proyectos) | Para qué |
|---|---|
| `zuma-rapido` | Preguntas cortas, jobs, clasificar |
| `zuma-chat` | Agente Gerente, usa herramientas. Si falla, cae a `zuma-rapido` |
| `zuma-vision` | Fotos de bodega y facturas |

Qué modelo real hay detrás lo decide el archivo de configuración:

- `config.yaml` → **PC de 48 GB**: qwen2.5:7b / qwen2.5:14b / qwen2.5vl:7b
- `config-laptop.yaml` → **portátil**: qwen2.5:1.5b / qwen2.5:7b / moondream

Se elige con `CONFIG_FILE` en el `.env`.

## Arrancar

```bash
cp .env.example .env     # y poner una clave larga en LITELLM_MASTER_KEY
# en la PC de 48 GB:
ollama pull qwen2.5:7b && ollama pull qwen2.5:14b && ollama pull qwen2.5vl:7b
sed -i 's/^CONFIG_FILE=.*/CONFIG_FILE=config.yaml/' .env

docker compose up -d
```

- Chat web: <http://localhost:3000>
- API: <http://localhost:4000>

> El contenedor de LiteLLM usa la red del host para alcanzar el Ollama que escucha en
> `127.0.0.1:11434`. Por eso no lleva `ports:`.

## Probar

```bash
set -a && . ./.env && set +a

# texto
curl -sS http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"model":"zuma-rapido","messages":[{"role":"user","content":"Responde solo: funciono"}]}'
```

Herramientas (lo que más falla con modelos chicos) y visión: ver `pruebas/` o los ejemplos
en el doc de Zuma `docs/agentes/plataforma-ia.md`.

### Resultado de la primera prueba (portátil, sin GPU, 2026-09-22)

| Prueba | Resultado |
|---|---|
| Texto (`zuma-rapido`, qwen2.5:1.5b) | ✅ Responde en 7,6 s |
| Herramientas (`zuma-chat`, qwen2.5:7b) | ✅ Eligió `inventario_critico` con `limite: 10`; añadió texto de más |
| Visión (`zuma-vision`, moondream) | ✅ Leyó el banner, pero con errores y respondió en inglés |

Conclusión: el circuito sirve. La calidad de estos modelos chicos **no** alcanza para
producción; para eso van los modelos grandes de `config.yaml` o una GPU alquilada.

## Conectar Zuma (staging)

```
DEEPSEEK_BASE_URL=http://127.0.0.1:4000/v1
DEEPSEEK_API_KEY=<la master key, o una clave virtual>
DEEPSEEK_MODEL=zuma-chat
```

La visión de Zuma todavía tiene la URL fija en el código
(`OpenRouterService::OPENROUTER_ENDPOINT`); hay que hacerla configurable primero.

## Siguiente paso: GPU por horas

Cuando esto convenza, se alquila una **RTX A6000 de 48 GB** en RunPod (~0,33 USD/hora),
se levanta **vLLM** en vez de Ollama y se apunta `api_base` allá. Los nombres de modelo y
los proyectos no cambian. Detalle en `docs/agentes/ia-local.md` del repo de Zuma.
