# IA local: que los datos no salgan del servidor

> ⏳ **Plan.** Aquí sí hace falta GPU. Complementa a [plataforma-ia.md](plataforma-ia.md);
> la prueba sin GPU está en [prueba-aws.md](prueba-aws.md).

Objetivo: el modelo corre **dentro de nuestro servidor**. Ningún prompt, foto ni dato de un
restaurante sale hacia DeepSeek, OpenAI o Google. Es el mismo argumento que vende Snowflake.

```
Zuma ──► Núcleo IA (LiteLLM) ──► vLLM en la misma máquina ──► GPU
                                  (Qwen / Llama, pesos nuestros)
         sin salida a internet
```

La arquitectura no cambia respecto al plan: solo cambia a quién llama LiteLLM por detrás.

## Lo que hay que aceptar

| Realidad | Detalle |
|---|---|
| La GPU se paga prendida | Se use o no. No hay "cero cuando nadie pregunta" |
| Calidad algo menor | Un modelo abierto de 7B–32B no responde como los modelos grandes comerciales |
| Sin respaldo externo | Si el objetivo es que nada salga, hay que **apagar los fallbacks** a proveedores |
| Mantenimiento | Actualizar modelos, vigilar la VRAM, reiniciar si se cae |

Si el servidor es alquilado (AWS, RunPod), los datos salen de tu oficina pero se quedan en tu
servidor, igual que hoy con Zuma. Si la exigencia es que no salgan del país o del edificio,
entonces toca hardware propio.

## Qué GPU: la RTX A6000 de 48 GB

Precios de RunPod consultados el 2026-09-22 ([runpod.io/pricing](https://www.runpod.io/pricing)).
Cobran por segundo, así que unas horas de prueba cuestan un par de dólares.

| GPU | VRAM | Community | Secure | Al mes (Secure) |
|---|---|---|---|---|
| **RTX A6000** ← elegida | 48 GB | 0,33 USD/h | 0,53 USD/h | ~387 USD |
| A40 | 48 GB | 0,35 USD/h | 0,49 USD/h | ~358 USD |
| RTX 4090 | 24 GB | 0,34 USD/h | 0,74 USD/h | ~540 USD |
| L4 | 24 GB | 0,44 USD/h | 0,49 USD/h | ~358 USD |
| L40S | 48 GB | 0,79 USD/h | 1,09 USD/h | ~796 USD |
| A100 80 GB | 80 GB | 1,19 USD/h | 1,59 USD/h | ~1.160 USD |

**Por qué la A6000 y no la 4090:** cuesta casi lo mismo y trae el doble de memoria. Con 48 GB
caben **dos modelos prendidos a la vez** (chat de 32B en 4 bits + visión para las fotos); con
24 GB hay que elegir uno o bajar ambos a 7B. La 4090 y la 5090 son más rápidas por token, pero
aquí pesa más la memoria: las consultas son cortas, no textos largos.

**Community vs Secure:** Community son máquinas de terceros, más baratas, sin control de dónde
están. Secure es el centro de datos de RunPod. Para probar, Community; para datos reales de
restaurantes, Secure — que es justo el punto de tener la IA local.

Aparte se paga el almacenamiento, alrededor de 0,10 USD por GB al mes, y los modelos pesan entre
15 y 40 GB.

Alternativas: AWS `g6e.xlarge` (L40S 48 GB) sale por ~1,86 USD/hora, bastante más caro que
RunPod. Hardware propio (RTX 5090 o A6000 + servidor) cuesta 2.500–4.000 USD una vez, y conviene
solo cuando el alquiler de un año lo supere.

> Comparación honesta: hoy, pagando por API, el gasto de Zuma en IA es de unos pocos dólares al
> mes. La GPU propia se justifica por **privacidad**, no por precio, hasta tener mucho volumen.

## Qué modelos usar

| Uso en Zuma | Modelo sugerido | Nota |
|---|---|---|
| Chat y herramientas | Qwen 2.5 32B Instruct (4 bits) o 7B si la VRAM aprieta | Qwen maneja bien `tools` |
| Foto → inventario | Qwen 2.5-VL (7B o 32B) | Es el que ve imágenes |
| OCR de facturas | El mismo Qwen-VL | Hay que comparar contra el Gemini actual |

Licencias: Qwen es Apache 2.0 (libre para vender); Llama tiene condiciones de Meta. Revisar
antes de cobrarle a un cliente.

## Plan de prueba (2–3 días)

**1. Alquilar una GPU por horas** (RunPod es lo más barato para probar). No comprar nada todavía.

**2. Levantar vLLM** con la API compatible con OpenAI:

```bash
docker run --gpus all -p 8000:8000 \
  -v ~/modelos:/root/.cache/huggingface \
  vllm/vllm-openai:latest \
  --model Qwen/Qwen2.5-7B-Instruct \
  --max-model-len 8192 \
  --api-key sk-interna
```

**3. Colgarlo de Núcleo IA**, agregando el modelo local al `config.yaml`:

```yaml
model_list:
  - model_name: zuma-local
    litellm_params:
      model: hosted_vllm/Qwen/Qwen2.5-7B-Instruct
      api_base: http://vllm:8000/v1
      api_key: sk-interna
```

**4. Probar lo que de verdad importa** (lo mismo de [prueba-aws.md](prueba-aws.md)):

- [ ] Responde en español correcto y con el tono del negocio.
- [ ] **Elige bien las herramientas** de Zuma y no inventa argumentos. Es la prueba que más
      falla con modelos pequeños.
- [ ] Reconoce productos en una foto real de bodega (con Qwen-VL).
- [ ] Lee una factura de proveedor tan bien como el Gemini de hoy.
- [ ] Velocidad: cuántos segundos tarda una respuesta del chat.
- [ ] Concurrencia: 5 o 10 peticiones a la vez sin que se dispare el tiempo.

**5. Comparar** cada prueba contra el modelo actual y anotar el resultado. Con eso se decide.

## Camino recomendado

1. Empezar por API (barato, rápido, ya casi listo).
2. Montar Núcleo IA para que Zuma no dependa de nadie.
3. Cuando un cliente exija que sus datos no salgan, o el volumen lo justifique, prender la GPU
   y agregar `zuma-local` al `config.yaml`. **Zuma no cambia ni una línea.**
4. Modelo mixto posible: lo sensible (fotos, facturas, datos de clientes) al modelo local, y lo
   general al modelo por API.
