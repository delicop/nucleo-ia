# Prueba de Núcleo IA en AWS

> ⏳ **Guía de prueba.** Objetivo: alquilar un servidor pequeño en AWS, levantar la API de IA
> propia ([plataforma-ia.md](plataforma-ia.md)) y hacerle peticiones reales. Dos días, poco dinero.

## ¿Hace falta tarjeta gráfica? No

Al inicio **no** se alquila GPU. Los modelos se pagan por API (DeepSeek, OpenRouter), así que la
GPU es del proveedor: nuestro servidor solo recibe la petición, la reenvía y devuelve la
respuesta. Es trabajo de red, no de cálculo, y con 2 GB de RAM sobra. Es lo mismo que hace Zuma
hoy, cuyo servidor tampoco tiene GPU.

La GPU haría falta solo si quisiéramos correr el modelo nosotros (Llama, Qwen sobre vLLM), y
cuesta entre 0,80 y 2 USD la hora alquilada, es decir **600 a 1.400 USD al mes prendida**, se use
o no. Pagar por API cuesta centavos por consulta y cero cuando nadie pregunta. Solo conviene la
GPU propia con muchísimo volumen (millones de consultas al mes) o si los datos no pueden salir
del servidor. Ese cambio no tocaría el código de Zuma: se cambia el modelo en el `config.yaml`.

## Qué se alquila y cuánto cuesta

| Recurso | Elección | Costo aproximado |
|---|---|---|
| Servidor | EC2 `t4g.small` (ARM, 2 vCPU, 2 GB), Ubuntu 24.04 | ~15 USD/mes, ~0,02 USD/hora |
| Disco | 20 GB gp3 | ~2 USD/mes |
| IP fija | Elastic IP (solo si se asocia a una instancia encendida) | Gratis mientras esté en uso |
| Salida de datos | Poca (solo texto y fotos hacia los proveedores) | Centavos |
| Modelos | DeepSeek / OpenRouter por uso | Lo que se consuma en la prueba: 5–10 USD alcanza |

**Total de la prueba: menos de 25 USD** si se apaga al terminar. Con la capa gratuita de AWS
puede salir aún menos el primer año, pero el `t4g.small` no siempre entra ahí; revisar la
factura a los dos días.

> ⚠️ Lo que se olvida y cobra igual: instancia encendida sin usar, discos de instancias
> borradas y Elastic IP sin asociar. Al terminar la prueba, borrar todo.

## Paso 1 — Crear el servidor (30 min)

En la consola de AWS → EC2 → Launch instance:

- **Nombre:** `nucleo-ia-prueba`
- **AMI:** Ubuntu Server 24.04 LTS (ARM 64)
- **Tipo:** `t4g.small`
- **Key pair:** crear una nueva y guardar el `.pem` (es la llave para entrar)
- **Disco:** 20 GB gp3
- **Security group** (el cortafuegos, lo más importante):
  - SSH (22) → **solo tu IP**, nunca `0.0.0.0/0`
  - Nada más abierto. El puerto 4000 **no** se expone a internet.

Entrar:

```bash
chmod 400 nucleo-ia.pem
ssh -i nucleo-ia.pem ubuntu@<IP-publica>
```

## Paso 2 — Instalar Docker (10 min)

```bash
sudo apt update && sudo apt install -y docker.io docker-compose-v2
sudo usermod -aG docker ubuntu && exit     # salir y volver a entrar para que aplique
```

## Paso 3 — Levantar Núcleo IA (20 min)

```bash
mkdir ~/nucleo-ia && cd ~/nucleo-ia
```

`config.yaml` (el mismo de [plataforma-ia.md](plataforma-ia.md)):

```yaml
model_list:
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

`docker-compose.yml`:

```yaml
services:
  nucleo-ia:
    image: ghcr.io/berriai/litellm:main-stable
    command: ["--config", "/app/config.yaml"]
    volumes:
      - ./config.yaml:/app/config.yaml
    env_file: .env
    ports:
      - "127.0.0.1:4000:4000"   # solo local: se entra por tunel SSH
    restart: unless-stopped
    depends_on: [db]

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: nucleo_ia
      POSTGRES_USER: nucleo
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - dbdata:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  dbdata:
```

`.env` (nunca se sube a git):

```
DEEPSEEK_API_KEY=...
OPENROUTER_API_KEY=...
LITELLM_MASTER_KEY=sk-una-clave-larga-y-aleatoria
POSTGRES_PASSWORD=otra-clave-larga
DATABASE_URL=postgresql://nucleo:otra-clave-larga@db:5432/nucleo_ia
```

```bash
docker compose up -d && docker compose logs -f nucleo-ia
```

## Paso 4 — Primera petición (10 min)

Desde el servidor:

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"model":"zuma-rapido","messages":[{"role":"user","content":"Responde solo: funciono"}]}'
```

Desde tu PC, sin abrir puertos (túnel SSH):

```bash
ssh -i nucleo-ia.pem -L 4000:127.0.0.1:4000 ubuntu@<IP-publica>
# y ya puedes usar http://localhost:4000 en tu maquina
```

## Paso 5 — Las pruebas que importan

- [ ] **Texto:** una pregunta del chat del dueño, p. ej. "resumen de ventas de ayer".
- [ ] **Herramientas:** mandar el `tools` de Zuma y ver si elige bien la herramienta.
- [ ] **Visión:** una foto real de la bodega en base64, a ver qué productos reconoce y si
      acierta las cantidades. Esta es la prueba clave para el agente Gerente.
- [ ] **Factura:** una factura de proveedor real por el mismo camino.
- [ ] **Fallback:** poner mal a propósito la clave de OpenRouter y ver que responde el modelo
      de respaldo.
- [ ] **Clave por proyecto:** crear la clave `zuma-prueba` con presupuesto y verificar que,
      al pasarse, LiteLLM la bloquea.

```bash
curl http://127.0.0.1:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"key_alias":"zuma-prueba","models":["zuma-rapido","zuma-vision"],"max_budget":5}'
```

- [ ] **Costo y latencia:** revisar en LiteLLM cuánto costó cada petición y cuánto tardó.

## Paso 6 — Conectar Zuma (opcional en esta prueba)

Solo con el `.env` de **staging**, nunca el de producción:

```
DEEPSEEK_BASE_URL=http://<IP-privada-o-tunel>:4000/v1
DEEPSEEK_API_KEY=<clave zuma-prueba>
DEEPSEEK_MODEL=zuma-rapido
```

Reiniciar `app` y `worker` de staging por el OPcache (ver `DESARROLLO-EN-SERVIDOR.md`).

> Si el servidor de Zuma y este de AWS son distintos, el puerto 4000 tendría que quedar
> visible entre ellos. Para la prueba es mejor no abrirlo: se usa el túnel SSH, o se levanta
> Núcleo IA en el mismo servidor donde ya vive Zuma.

## Paso 7 — Apagar y no seguir pagando

```bash
docker compose down
```

Y en la consola de AWS: **Terminate instance**, borrar el volumen EBS si quedó, y soltar la
Elastic IP si se creó. Verificar la factura en Billing → Cost Explorer a los dos días.

## Qué se decide con esta prueba

| Pregunta | Cómo se responde |
|---|---|
| ¿La foto sirve para el inventario? | Con las fotos reales del paso 5 |
| ¿Cuánto cuesta cada consulta? | Con el costo por petición que reporta LiteLLM |
| ¿Los modelos abiertos sirven de respaldo? | Comparando `zuma-vision` contra `zuma-vision-abierto` |
| ¿Vale la pena la plataforma propia? | Si conectar Zuma resultó ser solo cambiar el `.env` |

## Después de la prueba

- Si funciona: pasar a la fase 1 de [plataforma-ia.md](plataforma-ia.md), pero montándolo en el
  servidor donde ya vive Zuma, en red interna y sin puertos abiertos.
- Si el costo por foto es alto: subir la imagen comprimida y guardar en caché los resultados.
- Comprar o alquilar GPU solo cuando el gasto mensual por API supere el de tener una prendida.
